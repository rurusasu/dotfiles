from __future__ import annotations

import hashlib
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path, PurePosixPath
from unittest import mock

BOOTSTRAP_ROOT = Path(__file__).resolve().parents[3] / "scripts" / "python"
sys.path.insert(0, str(BOOTSTRAP_ROOT))

from hermes_bootstrap import git as git_module
from hermes_bootstrap import profile_sync
from hermes_bootstrap.github import GitAuth
from hermes_bootstrap.models import DistributionSource
from hermes_bootstrap.profile_snapshot import (
    ProfileSnapshot,
    SnapshotEntry,
)
from hermes_bootstrap.profile_sync import synchronize_prepared_profiles


class ProfileSyncTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.data_root = self.root / "data"
        self.data_root.mkdir(mode=0o700)
        self.auth = GitAuth("fixture-token")

    def git(self, cwd: Path, *arguments: str) -> str:
        environment = os.environ.copy()
        environment.update(
            {
                "GIT_CONFIG_GLOBAL": os.devnull,
                "GIT_CONFIG_NOSYSTEM": "1",
                "GIT_TERMINAL_PROMPT": "0",
            }
        )
        result = subprocess.run(
            (git_module._GIT_EXECUTABLE, *arguments),
            cwd=cwd,
            env=environment,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        return result.stdout.strip()

    def profile(self, name: str, remote: Path) -> DistributionSource:
        return DistributionSource(
            name=name,
            source=str(remote),
            ref="main",
            target=self.data_root / "profiles" / name,
            manifest_name="distribution.yaml",
        )

    def snapshot(self, declaration: DistributionSource) -> ProfileSnapshot:
        root = self.root / f"snapshot-{declaration.name}"
        root.mkdir(mode=0o700)
        manifest = (
            f"name: {declaration.name}\n"
            "version: 0.1.0\n"
            "hermes_requires: '>=0.18.2'\n"
            "distribution_owned: [SOUL.md]\n"
        ).encode("ascii")
        gitignore = b"/*\n!/.gitignore\n!/distribution.yaml\n!/SOUL.md\n"
        (root / ".gitignore").write_bytes(gitignore)
        (root / "distribution.yaml").write_bytes(manifest)
        (root / "SOUL.md").write_bytes(b"local\n")
        (root / "SOUL.md").chmod(0o644)
        return ProfileSnapshot(
            declaration=declaration,
            root=root,
            manifest_bytes=manifest,
            gitignore_bytes=gitignore,
            entries=(SnapshotEntry(PurePosixPath("SOUL.md"), 0o644),),
        )

    def seed_remote_files(
        self,
        remote: Path,
        name: str,
        files: dict[str, bytes],
    ) -> str:
        self.git(self.root, "init", "--bare", "--initial-branch=main", str(remote))
        seed = self.root / f"seed-{name}"
        self.git(self.root, "init", "--initial-branch=main", str(seed))
        for relative, content in files.items():
            target = seed / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(content)
            target.chmod(0o644)
        self.git(seed, "add", "-f", "-A", "--", ".")
        self.git(
            seed,
            "-c",
            "user.name=Fixture",
            "-c",
            "user.email=fixture@localhost",
            "commit",
            "-m",
            "seed",
        )
        self.git(seed, "remote", "add", "origin", str(remote))
        self.git(seed, "push", "origin", "main")
        return self.git(remote, "rev-parse", "refs/heads/main")

    def advance_remote(
        self,
        remote: Path,
    ) -> str:
        checkout = self.root / "concurrent-writer"
        self.git(self.root, "clone", "--quiet", "--branch", "main", str(remote), str(checkout))
        marker = checkout / "concurrent.md"
        marker.write_text("concurrent update\n", encoding="ascii")
        self.git(checkout, "add", "-f", "-A", "--", ".")
        self.git(
            checkout,
            "-c",
            "user.name=Racer",
            "-c",
            "user.email=racer@localhost",
            "commit",
            "--allow-empty",
            "-m",
            "concurrent update",
        )
        self.git(checkout, "push", "origin", "main")
        return self.git(remote, "rev-parse", "refs/heads/main")

    def test_real_publication_rejects_bulk_deletion_above_manifest_limit(self) -> None:
        remote = self.root / "profile-a.git"
        base = self.profile("profile-a", remote)
        declaration = DistributionSource(
            base.name,
            base.source,
            base.ref,
            base.target,
            base.manifest_name,
            base.source_commit,
            1,
        )
        snapshot = self.snapshot(declaration)
        self.seed_remote_files(
            remote,
            declaration.name,
            {"old-a.md": b"old\n", "old-b.md": b"old\n"},
        )

        dry_run = synchronize_prepared_profiles(
            (snapshot,), self.auth, dry_run=True
        )
        self.assertEqual(dry_run.exit_code, 0)
        self.assertEqual(len(dry_run.profiles[0].diff.deleted), 2)

        report = synchronize_prepared_profiles(
            (snapshot,), self.auth, dry_run=False
        )
        self.assertEqual(report.exit_code, 4)
        self.assertEqual(report.profiles[0].category, "deletion_limit_exceeded")
        self.assertEqual(
            self.git(remote, "ls-tree", "-r", "--name-only", "main").splitlines(),
            ["old-a.md", "old-b.md"],
        )

    def test_secret_filename_is_reported_without_exposing_the_token(self) -> None:
        remote = self.root / "profile-a.git"
        declaration = self.profile("profile-a", remote)
        snapshot = self.snapshot(declaration)
        secret_name = f"secret-{self.auth.token}.md"
        self.seed_remote_files(
            remote,
            declaration.name,
            {
                secret_name: b"credential marker\n",
            },
        )

        report = synchronize_prepared_profiles(
            (snapshot,), self.auth, dry_run=False
        )

        identifier = f".git-path-bytes/sha256-{hashlib.sha256(secret_name.encode()).hexdigest()}"
        result = report.profiles[0]
        self.assertEqual(result.status, "changed")
        self.assertEqual(
            [path.as_posix() for path in result.diff.deleted],
            [identifier],
        )
        serialized = repr(report.as_dict())
        self.assertNotIn(self.auth.token, serialized)
        self.assertNotIn(secret_name.encode().hex(), serialized)
        self.assertIn(identifier, serialized)
        self.assertNotIn(
            secret_name,
            self.git(remote, "ls-tree", "-r", "--name-only", "refs/heads/main"),
        )

    def test_non_fast_forward_fails_once_and_rerun_publishes_local_snapshot(self) -> None:
        remote = self.root / "profile-a.git"
        declaration = self.profile("profile-a", remote)
        snapshot = self.snapshot(declaration)
        self.seed_remote_files(remote, declaration.name, {"README.md": b"old\n"})
        original_run = profile_sync._run_git_bytes
        push_arguments: list[tuple[str, ...]] = []
        winning_commit = ""

        def conflict(arguments, cwd, environment, *, max_output_bytes):
            nonlocal winning_commit
            if arguments and arguments[0] == "push":
                push_arguments.append(arguments)
                winning_commit = self.advance_remote(remote)
            return original_run(
                arguments, cwd, environment, max_output_bytes=max_output_bytes
            )

        with mock.patch.object(profile_sync, "_run_git_bytes", side_effect=conflict):
            failed = synchronize_prepared_profiles(
                (snapshot,), self.auth, dry_run=False
            )

        self.assertEqual(len(push_arguments), 1)
        self.assertNotIn("--force", push_arguments[0])
        self.assertEqual(failed.exit_code, 4)
        self.assertEqual(failed.profiles[0].category, "push_rejected")
        self.assertIn("rerun sync-profiles", failed.profiles[0].message)
        self.assertEqual(self.git(remote, "rev-parse", "refs/heads/main"), winning_commit)
        self.assertEqual((snapshot.root / "SOUL.md").read_bytes(), b"local\n")

        report = synchronize_prepared_profiles(
            (snapshot,), self.auth, dry_run=False
        )

        result = report.profiles[0]
        self.assertEqual(result.status, "changed")
        self.assertEqual(result.commit, self.git(remote, "rev-parse", "refs/heads/main"))
        self.assertEqual(self.git(remote, "rev-parse", f"{result.commit}^"), winning_commit)
        self.assertEqual(self.git(remote, "show", f"{result.commit}:SOUL.md"), "local")


if __name__ == "__main__":
    unittest.main()
