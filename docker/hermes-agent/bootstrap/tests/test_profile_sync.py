from __future__ import annotations

import hashlib
import os
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path, PurePosixPath
from types import FrameType, TracebackType
from unittest import mock


BOOTSTRAP_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BOOTSTRAP_ROOT))

from hermes_bootstrap.github import GitAuth
from hermes_bootstrap import profile_sync
from hermes_bootstrap.models import BootstrapManifest, DistributionSource
from hermes_bootstrap.payload import SecretRedactor
from hermes_bootstrap.profile_snapshot import (
    PreparedProfiles,
    ProfileSnapshot,
    ProfileSnapshotError,
    SnapshotEntry,
)
from hermes_bootstrap.profile_sync import (
    ProfileDiff,
    ProfileSyncReport,
    ProfileSyncResult,
    failed_profile_report,
    synchronize_prepared_profiles,
    synchronize_profiles,
)
from hermes_bootstrap.repositories import _RepositoryLock


class ProfileSyncTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.data_root = self.root / "data"
        self.data_root.mkdir(mode=0o700)
        (self.data_root / "locks" / "repositories").mkdir(parents=True, mode=0o700)
        self.auth = GitAuth("fixture-token", SecretRedactor(("fixture-token",)))
        self.advance_count = 0

    def assert_exception_hides(self, error: BaseException, *markers: str) -> None:
        pending: list[object] = [error]
        visited: set[int] = set()
        while pending:
            value = pending.pop()
            if value is None or id(value) in visited:
                continue
            visited.add(id(value))
            if isinstance(value, str):
                for marker in markers:
                    self.assertNotIn(marker, value)
            elif isinstance(value, bytes):
                for marker in markers:
                    self.assertNotIn(marker.encode("utf-8"), value)
            elif isinstance(value, BaseException):
                pending.extend(
                    (value.__cause__, value.__context__, value.__traceback__, value.args)
                )
            elif isinstance(value, TracebackType):
                pending.extend((value.tb_frame, value.tb_next))
            elif isinstance(value, FrameType):
                if "hermes_bootstrap" in value.f_code.co_filename:
                    pending.extend(value.f_locals.values())
            elif isinstance(value, dict):
                pending.extend((*value.keys(), *value.values()))
            elif isinstance(value, (list, tuple, set, frozenset)):
                pending.extend(value)

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
            ("/usr/bin/git", *arguments),
            cwd=cwd,
            env=environment,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        return result.stdout.strip()

    def git_bytes(self, cwd: Path, *arguments: str) -> bytes:
        environment = os.environ.copy()
        environment.update(
            {
                "GIT_CONFIG_GLOBAL": os.devnull,
                "GIT_CONFIG_NOSYSTEM": "1",
                "GIT_TERMINAL_PROMPT": "0",
            }
        )
        result = subprocess.run(
            ("/usr/bin/git", *arguments),
            cwd=cwd,
            env=environment,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        return result.stdout

    def profile(
        self, name: str, remote: Path, *, ref: str = "main"
    ) -> DistributionSource:
        return DistributionSource(
            name=name,
            source=str(remote),
            ref=ref,
            target=self.data_root / "profiles" / name,
            manifest_name="distribution.yaml",
        )

    def manifest(self, *profiles: DistributionSource) -> BootstrapManifest:
        root = DistributionSource(
            "default",
            str(self.root / "root.git"),
            "main",
            self.data_root,
            "root-distribution.yaml",
        )
        return BootstrapManifest(1, self.data_root, (), root, profiles, ())

    def snapshot(
        self,
        declaration: DistributionSource,
        files: dict[str, bytes],
        *,
        modes: dict[str, int] | None = None,
    ) -> ProfileSnapshot:
        root = self.root / f"snapshot-{declaration.name}"
        root.mkdir(mode=0o700)
        manifest = (
            f"name: {declaration.name}\n"
            "version: 0.1.0\n"
            "hermes_requires: '>=0.18.2'\n"
            f"distribution_owned: [{', '.join(files)}]\n"
        ).encode("ascii")
        rules = ["/*", "!/.gitignore", "!/distribution.yaml"]
        for name in sorted(files):
            path = PurePosixPath(name)
            for depth in range(1, len(path.parts)):
                parent = "/".join(path.parts[:depth])
                allowance = f"!/{parent}/"
                if allowance not in rules:
                    rules.append(allowance)
            rules.append(f"!/{name}")
        gitignore = ("\n".join(rules) + "\n").encode("ascii")
        (root / ".gitignore").write_bytes(gitignore)
        (root / "distribution.yaml").write_bytes(manifest)
        entries = []
        for name, content in sorted(files.items()):
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
            mode = (modes or {}).get(name, 0o644)
            path.chmod(mode)
            entries.append(
                SnapshotEntry(
                    PurePosixPath(name),
                    mode,
                    len(content),
                    hashlib.sha256(content).hexdigest(),
                )
            )
        controls = (
            SnapshotEntry(
                PurePosixPath(".gitignore"),
                0o644,
                len(gitignore),
                hashlib.sha256(gitignore).hexdigest(),
            ),
            SnapshotEntry(
                PurePosixPath("distribution.yaml"),
                0o644,
                len(manifest),
                hashlib.sha256(manifest).hexdigest(),
            ),
        )
        digest_payload = b"".join(
            f"{entry.path.as_posix()}\0{entry.mode:o}\0{entry.sha256}\n".encode("ascii")
            for entry in sorted((*controls, *entries), key=lambda item: item.path.as_posix())
        )
        return ProfileSnapshot(
            declaration=declaration,
            root=root,
            manifest_bytes=manifest,
            gitignore_bytes=gitignore,
            entries=tuple(entries),
            digest=hashlib.sha256(digest_payload).hexdigest(),
        )

    def seed_remote(self, remote: Path, snapshot: ProfileSnapshot) -> str:
        files = {
            source.relative_to(snapshot.root).as_posix(): source.read_bytes()
            for source in snapshot.root.rglob("*")
            if source.is_file()
        }
        modes = {
            entry.path.as_posix(): entry.mode for entry in snapshot.entries
        }
        return self.seed_remote_files(
            remote, snapshot.declaration.name, files, modes=modes
        )

    def seed_remote_files(
        self,
        remote: Path,
        name: str,
        files: dict[str, bytes],
        *,
        modes: dict[str, int] | None = None,
    ) -> str:
        self.git(self.root, "init", "--bare", "--initial-branch=main", str(remote))
        self.addCleanup(self.git, remote, "fsck", "--strict")
        seed = self.root / f"seed-{name}"
        self.git(self.root, "init", "--initial-branch=main", str(seed))
        for relative, content in files.items():
            target = seed / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(content)
            target.chmod((modes or {}).get(relative, 0o644))
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
        *,
        snapshot: ProfileSnapshot | None = None,
    ) -> str:
        self.advance_count += 1
        checkout = self.root / f"advance-{self.advance_count}"
        self.git(self.root, "clone", "--quiet", "--branch", "main", str(remote), str(checkout))
        if snapshot is None:
            marker = checkout / f"race-{self.advance_count}.txt"
            marker.write_text(f"race {self.advance_count}\n", encoding="ascii")
        else:
            self.git(checkout, "rm", "-r", "-q", "--", ".")
            for source in snapshot.root.rglob("*"):
                if source.is_file():
                    destination = checkout / source.relative_to(snapshot.root)
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    destination.write_bytes(source.read_bytes())
            (checkout / ".gitignore").write_bytes(snapshot.gitignore_bytes)
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
            f"race {self.advance_count}",
        )
        self.git(checkout, "push", "origin", "main")
        return self.git(remote, "rev-parse", "refs/heads/main")

    def published_snapshot_digest(self, remote: Path, commit: str) -> str:
        records = self.git_bytes(remote, "ls-tree", "-r", "-z", commit)
        entries: list[tuple[str, int, str]] = []
        for record in records.rstrip(b"\0").split(b"\0"):
            metadata, raw_path = record.split(b"\t", 1)
            raw_mode, kind, _object_id = metadata.split(b" ")
            self.assertEqual(kind, b"blob")
            path = raw_path.decode("ascii")
            content = self.git_bytes(remote, "show", f"{commit}:{path}")
            entries.append(
                (
                    path,
                    int(raw_mode, 8) & 0o777,
                    hashlib.sha256(content).hexdigest(),
                )
            )
        payload = b"".join(
            f"{path}\0{mode:o}\0{sha256}\n".encode("ascii")
            for path, mode, sha256 in sorted(entries)
        )
        return hashlib.sha256(payload).hexdigest()

    def test_result_and_report_mappings_have_the_exact_public_shape(self) -> None:
        result = ProfileSyncResult(
            name="profile-a",
            status="changed",
            commit="a" * 40,
            snapshot="b" * 64,
            diff=ProfileDiff(
                added=(PurePosixPath("SOUL.md"),),
                modified=(PurePosixPath("distribution.yaml"),),
                deleted=(PurePosixPath("README.md"),),
            ),
            category="published",
            message="profile snapshot published",
        )
        report = ProfileSyncReport(False, (result,), 0)

        self.assertEqual(
            tuple(result.as_dict()),
            (
                "name",
                "status",
                "commit",
                "snapshot",
                "added",
                "modified",
                "deleted",
                "paths",
                "category",
                "message",
            ),
        )
        self.assertEqual(result.as_dict()["paths"], ["README.md", "SOUL.md", "distribution.yaml"])
        self.assertEqual(
            tuple(report.as_dict()),
            ("schema_version", "command", "dry_run", "status", "profiles"),
        )
        self.assertEqual(report.as_dict()["command"], "sync-profiles")
        self.assertEqual(report.as_dict()["status"], "changed")

    def test_failed_profile_report_preserves_all_configured_profiles_in_order(self) -> None:
        profiles = tuple(
            self.profile(name, self.root / f"{name}.git")
            for name in ("profile-a", "profile-b", "profile-c", "profile-d")
        )

        report = failed_profile_report(
            profiles,
            dry_run=True,
            category="credentials",
            message="Git credentials unavailable",
            exit_code=4,
        )

        self.assertEqual([item.name for item in report.profiles], [item.name for item in profiles])
        self.assertTrue(all(item.status == "failed" for item in report.profiles))
        self.assertTrue(all(item.snapshot == "" for item in report.profiles))
        self.assertEqual(report.exit_code, 4)

    def test_identical_tree_is_unchanged_without_creating_a_commit(self) -> None:
        remote = self.root / "profile-a.git"
        declaration = self.profile("profile-a", remote)
        snapshot = self.snapshot(declaration, {"SOUL.md": b"safe local profile\n"})
        original = self.seed_remote(remote, snapshot)

        report = synchronize_prepared_profiles(
            PreparedProfiles((snapshot,), ()), self.auth, dry_run=False
        )

        self.assertEqual(report.exit_code, 0)
        self.assertEqual(len(report.profiles), 1)
        result = report.profiles[0]
        self.assertEqual(result.status, "unchanged")
        self.assertEqual(result.commit, original)
        self.assertEqual(result.snapshot, snapshot.digest)
        self.assertEqual(result.diff, ProfileDiff())
        self.assertEqual(self.git(remote, "rev-parse", "refs/heads/main"), original)
        serialized = str(report.as_dict())
        self.assertNotIn(str(snapshot.root), serialized)
        self.assertNotIn("safe local profile", serialized)
        self.assertEqual(result.as_dict()["paths"], [])

    def test_published_tree_is_exact_and_matches_the_task1_snapshot_digest(self) -> None:
        remote = self.root / "profile-a.git"
        declaration = self.profile("profile-a", remote)
        snapshot = self.snapshot(
            declaration,
            {"SOUL.md": b"profile\n", "bin/tool": b"#!/bin/sh\nexit 0\n"},
            modes={"bin/tool": 0o755},
        )
        self.seed_remote_files(remote, declaration.name, {"README.md": b"old\n"})

        report = synchronize_prepared_profiles(
            PreparedProfiles((snapshot,), ()), self.auth, dry_run=False
        )

        result = report.profiles[0]
        self.assertEqual(result.status, "changed")
        self.assertIsNotNone(result.commit)
        assert result.commit is not None
        self.assertEqual(
            self.git(remote, "ls-tree", "-r", "--name-only", result.commit).splitlines(),
            [".gitignore", "SOUL.md", "bin/tool", "distribution.yaml"],
        )
        self.assertEqual(
            self.git_bytes(remote, "show", f"{result.commit}:.gitignore"),
            snapshot.gitignore_bytes,
        )
        self.assertEqual(result.snapshot, snapshot.digest)
        self.assertEqual(
            self.published_snapshot_digest(remote, result.commit), snapshot.digest
        )
        self.assertTrue((snapshot.root / "bin/tool").stat().st_mode & stat.S_IXUSR)
        self.assertTrue(
            self.git(remote, "ls-tree", result.commit, "bin/tool").startswith("100755 blob ")
        )

    def test_staged_modes_must_match_controls_and_each_snapshot_entry(self) -> None:
        remote = self.root / "profile-a.git"
        declaration = self.profile("profile-a", remote)
        snapshot = self.snapshot(
            declaration,
            {"bin/tool": b"#!/bin/sh\nexit 0\n"},
            modes={"bin/tool": 0o755},
        )
        self.seed_remote(remote, snapshot)
        original_run = profile_sync._run_git_bytes

        def mismatched_owned(arguments, cwd, environment, *, max_output_bytes):
            output = original_run(
                arguments, cwd, environment, max_output_bytes=max_output_bytes
            )
            if arguments[:2] == ("ls-files", "--stage") and output is not None:
                output = output.replace(b"100755 ", b"100644 ", 1)
            return output

        with mock.patch.object(
            profile_sync, "_run_git_bytes", side_effect=mismatched_owned
        ):
            owned = synchronize_prepared_profiles(
                PreparedProfiles((snapshot,), ()), self.auth, dry_run=False
            )
        self.assertEqual(owned.profiles[0].status, "failed")

        def executable_control(arguments, cwd, environment, *, max_output_bytes):
            output = original_run(
                arguments, cwd, environment, max_output_bytes=max_output_bytes
            )
            if arguments[:2] == ("ls-files", "--stage") and output is not None:
                output = output.replace(b"100644 ", b"100755 ", 1)
            return output

        with mock.patch.object(
            profile_sync, "_run_git_bytes", side_effect=executable_control
        ):
            control = synchronize_prepared_profiles(
                PreparedProfiles((snapshot,), ()), self.auth, dry_run=False
            )
        self.assertEqual(control.profiles[0].status, "failed")

    def test_changed_tree_replaces_the_remote_with_the_exact_local_projection(self) -> None:
        remote = self.root / "profile-a.git"
        declaration = self.profile("profile-a", remote)
        snapshot = self.snapshot(
            declaration,
            {
                "SOUL.md": b"new local instructions\n",
                "assets/avatar.bin": b"\x00\xff\x10local-binary\x00",
            },
        )
        original = self.seed_remote_files(
            remote,
            declaration.name,
            {
                ".gitignore": b"*\n",
                "distribution.yaml": b"name: stale\n",
                "SOUL.md": b"old remote instructions\n",
                "assets": b"conflicting remote file\n",
                ".github/workflows/ci.yml": b"remote only\n",
                "README.md": b"remote only\n",
                "tests/test_old.py": b"remote only\n",
                "scripts/obsolete.sh": b"remote only\n",
            },
        )

        report = synchronize_prepared_profiles(
            PreparedProfiles((snapshot,), ()), self.auth, dry_run=False
        )

        result = report.profiles[0]
        self.assertEqual(report.exit_code, 0)
        self.assertEqual(result.status, "changed")
        self.assertIsNotNone(result.commit)
        self.assertNotEqual(result.commit, original)
        self.assertEqual(
            result.diff.added,
            (PurePosixPath("assets/avatar.bin"),),
        )
        self.assertEqual(
            result.diff.modified,
            (
                PurePosixPath(".gitignore"),
                PurePosixPath("SOUL.md"),
                PurePosixPath("distribution.yaml"),
            ),
        )
        self.assertEqual(
            result.diff.deleted,
            tuple(
                PurePosixPath(path)
                for path in (
                    ".github/workflows/ci.yml",
                    "README.md",
                    "assets",
                    "scripts/obsolete.sh",
                    "tests/test_old.py",
                )
            ),
        )
        remote_head = self.git(remote, "rev-parse", "refs/heads/main")
        self.assertEqual(result.commit, remote_head)
        self.assertEqual(self.git(remote, "rev-parse", f"{remote_head}^"), original)
        self.assertEqual(
            self.git(remote, "ls-tree", "-r", "--name-only", remote_head).splitlines(),
            [
                ".gitignore",
                "SOUL.md",
                "assets/avatar.bin",
                "distribution.yaml",
            ],
        )
        self.assertEqual(
            self.git_bytes(remote, "show", f"{remote_head}:assets/avatar.bin"),
            b"\x00\xff\x10local-binary\x00",
        )

        second = synchronize_prepared_profiles(
            PreparedProfiles((snapshot,), ()), self.auth, dry_run=False
        )
        self.assertEqual(second.profiles[0].status, "unchanged")
        self.assertEqual(second.profiles[0].commit, remote_head)

    def test_dry_run_reports_sorted_changes_without_moving_or_leaking(self) -> None:
        remote = self.root / "profile-a.git"
        declaration = self.profile("profile-a", remote)
        secret_marker = b"fixture-owned-file-marker"
        snapshot = self.snapshot(
            declaration,
            {"SOUL.md": secret_marker, "assets/avatar.bin": b"\x00\xffbinary"},
        )
        original = self.seed_remote_files(
            remote,
            declaration.name,
            {
                ".gitignore": b"*\n",
                "distribution.yaml": b"name: stale\n",
                "SOUL.md": b"old\n",
                "README.md": b"remote only\n",
            },
        )

        report = synchronize_prepared_profiles(
            PreparedProfiles((snapshot,), ()), self.auth, dry_run=True
        )

        result = report.profiles[0]
        self.assertEqual(report.exit_code, 0)
        self.assertEqual(result.status, "changed")
        self.assertEqual(result.commit, original)
        self.assertEqual(
            [path.as_posix() for path in result.diff.added],
            ["assets/avatar.bin"],
        )
        self.assertEqual(
            [path.as_posix() for path in result.diff.modified],
            [".gitignore", "SOUL.md", "distribution.yaml"],
        )
        self.assertEqual(
            [path.as_posix() for path in result.diff.deleted], ["README.md"]
        )
        self.assertEqual(self.git(remote, "rev-parse", "refs/heads/main"), original)
        serialized = str(report.as_dict())
        self.assertNotIn(self.auth.token, serialized)
        self.assertNotIn(secret_marker.decode("ascii"), serialized)
        self.assertNotIn(str(snapshot.root), serialized)

    def test_first_non_fast_forward_rebuilds_once_on_the_new_remote_head(self) -> None:
        remote = self.root / "profile-a.git"
        declaration = self.profile("profile-a", remote)
        snapshot = self.snapshot(declaration, {"SOUL.md": b"local\n"})
        self.seed_remote_files(remote, declaration.name, {"README.md": b"old\n"})
        original_run = profile_sync._run_git_bytes
        push_calls = 0

        def race(arguments, cwd, environment, *, max_output_bytes):
            nonlocal push_calls
            if arguments and arguments[0] == "push":
                push_calls += 1
                if push_calls == 1:
                    self.advance_remote(remote)
            return original_run(
                arguments, cwd, environment, max_output_bytes=max_output_bytes
            )

        with mock.patch.object(profile_sync, "_run_git_bytes", side_effect=race):
            report = synchronize_prepared_profiles(
                PreparedProfiles((snapshot,), ()), self.auth, dry_run=False
            )

        result = report.profiles[0]
        self.assertEqual(result.status, "changed")
        self.assertEqual(push_calls, 2)
        self.assertEqual(result.commit, self.git(remote, "rev-parse", "refs/heads/main"))
        self.assertEqual(
            self.git(remote, "ls-tree", "-r", "--name-only", result.commit).splitlines(),
            [".gitignore", "SOUL.md", "distribution.yaml"],
        )

    def test_invalid_destination_branch_fails_unchanged_and_dry_run_paths(self) -> None:
        unchanged_remote = self.root / "unchanged.git"
        unchanged_declaration = self.profile(
            "unchanged-profile", unchanged_remote, ref="HEAD"
        )
        unchanged_snapshot = self.snapshot(
            unchanged_declaration, {"SOUL.md": b"same\n"}
        )
        self.seed_remote(unchanged_remote, unchanged_snapshot)

        unchanged = synchronize_prepared_profiles(
            PreparedProfiles((unchanged_snapshot,), ()), self.auth, dry_run=False
        )

        dry_remote = self.root / "dry.git"
        dry_declaration = self.profile(
            "dry-profile", dry_remote, ref="refs/heads/main"
        )
        dry_snapshot = self.snapshot(dry_declaration, {"SOUL.md": b"local\n"})
        self.seed_remote_files(dry_remote, dry_declaration.name, {"README.md": b"old\n"})

        dry = synchronize_prepared_profiles(
            PreparedProfiles((dry_snapshot,), ()), self.auth, dry_run=True
        )

        invalid = self.snapshot(
            self.profile("invalid-profile", dry_remote, ref="main..bad"),
            {"SOUL.md": b"local\n"},
        )
        invalid_result = synchronize_prepared_profiles(
            PreparedProfiles((invalid,), ()), self.auth, dry_run=True
        )

        self.assertEqual(unchanged.profiles[0].status, "failed")
        self.assertEqual(dry.profiles[0].status, "failed")
        self.assertEqual(invalid_result.profiles[0].status, "failed")

    def test_second_non_fast_forward_exhausts_the_single_retry(self) -> None:
        remote = self.root / "profile-a.git"
        declaration = self.profile("profile-a", remote)
        snapshot = self.snapshot(declaration, {"SOUL.md": b"local\n"})
        self.seed_remote_files(remote, declaration.name, {"README.md": b"old\n"})
        original_run = profile_sync._run_git_bytes
        push_calls = 0

        def race(arguments, cwd, environment, *, max_output_bytes):
            nonlocal push_calls
            if arguments and arguments[0] == "push":
                push_calls += 1
                self.advance_remote(remote)
            return original_run(
                arguments, cwd, environment, max_output_bytes=max_output_bytes
            )

        with mock.patch.object(profile_sync, "_run_git_bytes", side_effect=race):
            report = synchronize_prepared_profiles(
                PreparedProfiles((snapshot,), ()), self.auth, dry_run=False
            )

        self.assertEqual(push_calls, 2)
        self.assertEqual(report.exit_code, 4)
        self.assertEqual(report.profiles[0].category, "push_race_exhausted")

    def test_remote_advance_with_the_same_tree_is_accepted(self) -> None:
        remote = self.root / "profile-a.git"
        declaration = self.profile("profile-a", remote)
        snapshot = self.snapshot(declaration, {"SOUL.md": b"local\n"})
        self.seed_remote_files(remote, declaration.name, {"README.md": b"old\n"})
        original_run = profile_sync._run_git_bytes
        push_calls = 0
        winning_commit = ""

        def race(arguments, cwd, environment, *, max_output_bytes):
            nonlocal push_calls, winning_commit
            if arguments and arguments[0] == "push":
                push_calls += 1
                if push_calls == 1:
                    winning_commit = self.advance_remote(remote, snapshot=snapshot)
            return original_run(
                arguments, cwd, environment, max_output_bytes=max_output_bytes
            )

        with mock.patch.object(profile_sync, "_run_git_bytes", side_effect=race):
            report = synchronize_prepared_profiles(
                PreparedProfiles((snapshot,), ()), self.auth, dry_run=False
            )

        self.assertEqual(push_calls, 1)
        self.assertEqual(report.profiles[0].status, "changed")
        self.assertEqual(report.profiles[0].commit, winning_commit)

    def test_different_tree_after_successful_push_retries_on_the_new_head(self) -> None:
        remote = self.root / "profile-a.git"
        declaration = self.profile("profile-a", remote)
        snapshot = self.snapshot(declaration, {"SOUL.md": b"local\n"})
        self.seed_remote_files(remote, declaration.name, {"README.md": b"old\n"})
        original_run = profile_sync._run_git_bytes
        push_calls = 0
        raced_commit = ""

        def race_after_push(arguments, cwd, environment, *, max_output_bytes):
            nonlocal push_calls, raced_commit
            output = original_run(
                arguments, cwd, environment, max_output_bytes=max_output_bytes
            )
            if arguments and arguments[0] == "push" and output is not None:
                push_calls += 1
                if push_calls == 1:
                    raced_commit = self.advance_remote(remote)
            return output

        with mock.patch.object(
            profile_sync, "_run_git_bytes", side_effect=race_after_push
        ):
            report = synchronize_prepared_profiles(
                PreparedProfiles((snapshot,), ()), self.auth, dry_run=False
            )

        result = report.profiles[0]
        self.assertEqual(result.status, "changed")
        self.assertEqual(push_calls, 2)
        self.assertEqual(result.commit, self.git(remote, "rev-parse", "refs/heads/main"))
        self.assertEqual(self.git(remote, "rev-parse", f"{result.commit}^"), raced_commit)
        self.assertEqual(
            self.git(remote, "ls-tree", "-r", "--name-only", result.commit).splitlines(),
            [".gitignore", "SOUL.md", "distribution.yaml"],
        )

    def test_different_tree_after_successful_retry_exhausts_the_race(self) -> None:
        remote = self.root / "profile-a.git"
        declaration = self.profile("profile-a", remote)
        snapshot = self.snapshot(declaration, {"SOUL.md": b"local\n"})
        self.seed_remote_files(remote, declaration.name, {"README.md": b"old\n"})
        original_run = profile_sync._run_git_bytes
        push_calls = 0

        def race_after_each_push(arguments, cwd, environment, *, max_output_bytes):
            nonlocal push_calls
            output = original_run(
                arguments, cwd, environment, max_output_bytes=max_output_bytes
            )
            if arguments and arguments[0] == "push" and output is not None:
                push_calls += 1
                self.advance_remote(remote)
            return output

        with mock.patch.object(
            profile_sync, "_run_git_bytes", side_effect=race_after_each_push
        ):
            report = synchronize_prepared_profiles(
                PreparedProfiles((snapshot,), ()), self.auth, dry_run=False
            )

        self.assertEqual(push_calls, 2)
        self.assertEqual(report.exit_code, 4)
        self.assertEqual(report.profiles[0].category, "push_race_exhausted")

    def test_same_tree_descendant_after_successful_push_is_accepted(self) -> None:
        remote = self.root / "profile-a.git"
        declaration = self.profile("profile-a", remote)
        snapshot = self.snapshot(declaration, {"SOUL.md": b"local\n"})
        self.seed_remote_files(remote, declaration.name, {"README.md": b"old\n"})
        original_run = profile_sync._run_git_bytes
        winning_commit = ""
        push_calls = 0

        def same_tree_after_push(arguments, cwd, environment, *, max_output_bytes):
            nonlocal winning_commit, push_calls
            output = original_run(
                arguments, cwd, environment, max_output_bytes=max_output_bytes
            )
            if arguments and arguments[0] == "push" and output is not None:
                push_calls += 1
                if push_calls == 1:
                    winning_commit = self.advance_remote(remote, snapshot=snapshot)
            return output

        with mock.patch.object(
            profile_sync, "_run_git_bytes", side_effect=same_tree_after_push
        ):
            report = synchronize_prepared_profiles(
                PreparedProfiles((snapshot,), ()), self.auth, dry_run=False
            )

        self.assertEqual(push_calls, 1)
        self.assertEqual(report.profiles[0].status, "changed")
        self.assertEqual(report.profiles[0].commit, winning_commit)

    def test_push_rejection_without_remote_advance_is_not_reported_as_a_race(self) -> None:
        remote = self.root / "profile-a.git"
        declaration = self.profile("profile-a", remote)
        snapshot = self.snapshot(declaration, {"SOUL.md": b"local\n"})
        original = self.seed_remote_files(remote, declaration.name, {"README.md": b"old\n"})
        original_run = profile_sync._run_git_bytes

        def reject(arguments, cwd, environment, *, max_output_bytes):
            if arguments and arguments[0] == "push":
                return None
            return original_run(
                arguments, cwd, environment, max_output_bytes=max_output_bytes
            )

        with mock.patch.object(profile_sync, "_run_git_bytes", side_effect=reject):
            report = synchronize_prepared_profiles(
                PreparedProfiles((snapshot,), ()), self.auth, dry_run=False
            )

        self.assertEqual(report.profiles[0].category, "push_rejected")
        self.assertEqual(self.git(remote, "rev-parse", "refs/heads/main"), original)

    def test_lock_contention_hardlink_and_replacement_fail_closed(self) -> None:
        remote = self.root / "profile-a.git"
        declaration = self.profile("profile-a", remote)
        snapshot = self.snapshot(declaration, {"SOUL.md": b"local\n"})
        self.seed_remote(remote, snapshot)
        prepared = PreparedProfiles((snapshot,), ())
        lock = self.data_root / "locks" / "repositories" / "profile-profile-a.lock"

        with _RepositoryLock(lock, self.data_root):
            busy = synchronize_prepared_profiles(prepared, self.auth, dry_run=False)
        self.assertEqual(busy.profiles[0].category, "lock_busy")

        outside = self.root / "outside-lock"
        os.link(lock, outside)
        hardlinked = synchronize_prepared_profiles(prepared, self.auth, dry_run=False)
        self.assertEqual(hardlinked.profiles[0].status, "failed")
        outside.unlink()

        original_attempt = profile_sync._exact_tree_attempt

        def replace_lock(*arguments):
            attempt = original_attempt(*arguments)
            lock.unlink()
            lock.write_text("replacement", encoding="ascii")
            return attempt

        with mock.patch.object(profile_sync, "_exact_tree_attempt", side_effect=replace_lock):
            replaced = synchronize_prepared_profiles(prepared, self.auth, dry_run=False)
        self.assertEqual(replaced.profiles[0].status, "failed")

    def test_git_output_overflow_and_wrong_remote_identity_are_redacted(self) -> None:
        remote = self.root / "profile-a.git"
        declaration = self.profile("profile-a", remote)
        owned_marker = "owned-file-content-marker"
        snapshot = self.snapshot(declaration, {"SOUL.md": owned_marker.encode("ascii")})
        self.seed_remote(remote, snapshot)
        original_run = profile_sync._run_git_bytes

        def overflow(arguments, cwd, environment, *, max_output_bytes):
            limit = 1 if arguments[:2] == ("ls-files", "--stage") else max_output_bytes
            return original_run(arguments, cwd, environment, max_output_bytes=limit)

        with mock.patch.object(profile_sync, "_run_git_bytes", side_effect=overflow):
            overflow_report = synchronize_prepared_profiles(
                PreparedProfiles((snapshot,), ()), self.auth, dry_run=False
            )
        self.assertEqual(overflow_report.profiles[0].status, "failed")

        def wrong_identity(arguments, cwd, environment, *, max_output_bytes):
            if arguments[:3] == ("config", "--get", "remote.origin.url"):
                return b"/wrong/remote.git\n"
            return original_run(
                arguments, cwd, environment, max_output_bytes=max_output_bytes
            )

        with mock.patch.object(profile_sync, "_run_git_bytes", side_effect=wrong_identity):
            identity_report = synchronize_prepared_profiles(
                PreparedProfiles((snapshot,), ()), self.auth, dry_run=False
            )
        serialized = repr((overflow_report.as_dict(), identity_report.as_dict()))
        self.assertEqual(identity_report.profiles[0].status, "failed")
        self.assertNotIn(self.auth.token, serialized)
        self.assertNotIn(owned_marker, serialized)
        self.assertNotIn(str(snapshot.root), serialized)

    def test_private_git_resources_are_removed_on_success_and_failure(self) -> None:
        remote = self.root / "profile-a.git"
        declaration = self.profile("profile-a", remote)
        snapshot = self.snapshot(declaration, {"SOUL.md": b"local\n"})
        self.seed_remote(remote, snapshot)
        prepared = PreparedProfiles((snapshot,), ())

        synchronize_prepared_profiles(prepared, self.auth, dry_run=False)
        self.assertEqual(list(self.data_root.glob("askpass-*")), [])
        self.assertEqual(list(self.data_root.glob(".hermes-profile-sync-*")), [])

        with mock.patch.object(profile_sync, "_run_git_bytes", return_value=None):
            synchronize_prepared_profiles(prepared, self.auth, dry_run=False)
        self.assertEqual(list(self.data_root.glob("askpass-*")), [])
        self.assertEqual(list(self.data_root.glob(".hermes-profile-sync-*")), [])

        with mock.patch.object(profile_sync, "_unlink", return_value=False):
            cleanup = synchronize_prepared_profiles(prepared, self.auth, dry_run=False)
        self.assertEqual(cleanup.profiles[0].category, "cleanup_failed")

    def test_unexpected_askpass_cleanup_exception_is_scrubbed_and_continues(self) -> None:
        first_remote = self.root / "first.git"
        second_remote = self.root / "second.git"
        owned_marker = "askpass-owned-marker"
        first = self.snapshot(
            self.profile("first-profile", first_remote),
            {"SOUL.md": owned_marker.encode("ascii")},
        )
        second = self.snapshot(
            self.profile("second-profile", second_remote), {"SOUL.md": b"second\n"}
        )
        self.seed_remote(first_remote, first)
        self.seed_remote(second_remote, second)
        original_unlink = profile_sync._unlink
        original_remove = profile_sync._remove_tree
        captured: list[BaseException] = []
        removed: list[Path] = []
        calls = 0

        def unlink(path: Path) -> bool:
            nonlocal calls
            calls += 1
            if calls == 1:
                try:
                    raise ValueError(owned_marker)
                except ValueError as cause:
                    error = RuntimeError(self.auth.token)
                    error.__cause__ = cause
                    captured.append(error)
                    raise error
            return original_unlink(path)

        def remove(path: Path) -> bool:
            removed.append(path)
            return original_remove(path)

        with (
            mock.patch.object(profile_sync, "_unlink", side_effect=unlink),
            mock.patch.object(profile_sync, "_remove_tree", side_effect=remove),
        ):
            report = synchronize_prepared_profiles(
                PreparedProfiles((first, second), ()), self.auth, dry_run=False
            )

        self.assertEqual(
            [item.status for item in report.profiles], ["failed", "unchanged"]
        )
        self.assertEqual(report.profiles[0].category, "cleanup_failed")
        self.assertEqual(len(removed), 2)
        self.assertNotIn(self.auth.token, repr(report.as_dict()))
        self.assertNotIn(owned_marker, repr(report.as_dict()))
        self.assertEqual(len(captured), 1)
        self.assert_exception_hides(captured[0], self.auth.token, owned_marker)

    def test_unexpected_repository_cleanup_exception_is_scrubbed_and_continues(self) -> None:
        first_remote = self.root / "first.git"
        second_remote = self.root / "second.git"
        owned_marker = "repository-owned-marker"
        first = self.snapshot(
            self.profile("first-profile", first_remote),
            {"SOUL.md": owned_marker.encode("ascii")},
        )
        second = self.snapshot(
            self.profile("second-profile", second_remote), {"SOUL.md": b"second\n"}
        )
        self.seed_remote(first_remote, first)
        self.seed_remote(second_remote, second)
        original_remove = profile_sync._remove_tree
        captured: list[BaseException] = []
        calls = 0

        def remove(path: Path) -> bool:
            nonlocal calls
            calls += 1
            if calls == 1:
                error = RuntimeError(self.auth.token, owned_marker)
                captured.append(error)
                raise error
            return original_remove(path)

        with mock.patch.object(profile_sync, "_remove_tree", side_effect=remove):
            report = synchronize_prepared_profiles(
                PreparedProfiles((first, second), ()), self.auth, dry_run=False
            )

        self.assertEqual(
            [item.status for item in report.profiles], ["failed", "unchanged"]
        )
        self.assertEqual(report.profiles[0].category, "cleanup_failed")
        self.assertEqual(calls, 2)
        serialized = repr(report.as_dict())
        self.assertNotIn(self.auth.token, serialized)
        self.assertNotIn(owned_marker, serialized)
        self.assert_exception_hides(captured[0], self.auth.token, owned_marker)

    def test_unexpected_snapshot_cleanup_exception_is_scrubbed_after_all_profiles(self) -> None:
        first_remote = self.root / "first.git"
        second_remote = self.root / "second.git"
        owned_marker = "snapshot-owned-marker"
        first_declaration = self.profile("first-profile", first_remote)
        second_declaration = self.profile("second-profile", second_remote)
        first = self.snapshot(
            first_declaration, {"SOUL.md": owned_marker.encode("ascii")}
        )
        second = self.snapshot(
            second_declaration, {"SOUL.md": b"second\n"}
        )
        self.seed_remote(first_remote, first)
        self.seed_remote(second_remote, second)
        manifest = self.manifest(first_declaration, second_declaration)
        original_remove = profile_sync._remove_tree
        original_sync_one = profile_sync._synchronize_one_boundary
        captured: list[BaseException] = []
        attempted: list[str] = []

        def remove(path: Path) -> bool:
            if path.name.startswith(".hermes-profile-snapshots-"):
                error = RuntimeError(self.auth.token, owned_marker)
                captured.append(error)
                raise error
            return original_remove(path)

        def sync_one(snapshot, auth, dry_run):
            attempted.append(snapshot.declaration.name)
            return original_sync_one(snapshot, auth, dry_run)

        with (
            mock.patch.object(
                profile_sync,
                "prepare_profile_snapshots",
                return_value=PreparedProfiles((first, second), ()),
            ),
            mock.patch.object(profile_sync, "_remove_tree", side_effect=remove),
            mock.patch.object(
                profile_sync, "_synchronize_one_boundary", side_effect=sync_one
            ),
        ):
            report = synchronize_profiles(manifest, self.auth, dry_run=False)

        self.assertEqual(attempted, ["first-profile", "second-profile"])
        self.assertTrue(
            all(item.category == "cleanup_failed" for item in report.profiles)
        )
        serialized = repr(report.as_dict())
        self.assertNotIn(self.auth.token, serialized)
        self.assertNotIn(owned_marker, serialized)
        self.assert_exception_hides(captured[0], self.auth.token, owned_marker)

    def test_profile_failures_continue_in_prepared_order(self) -> None:
        good_remote = self.root / "good.git"
        bad_remote = self.root / "missing.git"
        bad = self.snapshot(self.profile("bad-profile", bad_remote), {"SOUL.md": b"bad\n"})
        good = self.snapshot(self.profile("good-profile", good_remote), {"SOUL.md": b"good\n"})
        self.seed_remote(good_remote, good)

        report = synchronize_prepared_profiles(
            PreparedProfiles((bad, good), ()), self.auth, dry_run=False
        )

        self.assertEqual([item.name for item in report.profiles], ["bad-profile", "good-profile"])
        self.assertEqual([item.status for item in report.profiles], ["failed", "unchanged"])
        self.assertEqual(report.exit_code, 4)

    def test_synchronize_profiles_cleans_scratch_and_maps_preflight_failures(self) -> None:
        remote_a = self.root / "profile-a.git"
        remote_b = self.root / "profile-b.git"
        profile_a = self.profile("profile-a", remote_a)
        profile_b = self.profile("profile-b", remote_b)
        snapshot_a = self.snapshot(profile_a, {"SOUL.md": b"a\n"})
        snapshot_b = self.snapshot(profile_b, {"SOUL.md": b"b\n"})
        self.seed_remote(remote_a, snapshot_a)
        self.seed_remote(remote_b, snapshot_b)
        manifest = self.manifest(profile_a, profile_b)
        observed_scratch: list[Path] = []

        def prepared(_manifest, scratch, *, allow_missing):
            self.assertIs(_manifest, manifest)
            self.assertFalse(allow_missing)
            self.assertEqual(stat.S_IMODE(scratch.stat().st_mode), 0o700)
            observed_scratch.append(scratch)
            return PreparedProfiles((snapshot_a, snapshot_b), ())

        with mock.patch.object(profile_sync, "prepare_profile_snapshots", side_effect=prepared):
            report = synchronize_profiles(manifest, self.auth, dry_run=False)
        self.assertEqual([item.status for item in report.profiles], ["unchanged", "unchanged"])
        self.assertTrue(observed_scratch)
        self.assertFalse(observed_scratch[0].exists())

        with mock.patch.object(
            profile_sync,
            "prepare_profile_snapshots",
            side_effect=ProfileSnapshotError("profile-b", "invalid_local_profile"),
        ):
            failed = synchronize_profiles(manifest, self.auth, dry_run=True)
        self.assertEqual([item.name for item in failed.profiles], ["profile-a", "profile-b"])
        self.assertEqual(
            [item.category for item in failed.profiles],
            ["aggregate_preflight_blocked", "invalid_local_profile"],
        )
        self.assertEqual(failed.exit_code, 4)

        with (
            mock.patch.object(profile_sync, "prepare_profile_snapshots", side_effect=prepared),
            mock.patch.object(profile_sync, "_remove_tree", return_value=False),
        ):
            cleanup = synchronize_profiles(manifest, self.auth, dry_run=False)
        self.assertTrue(all(item.category == "cleanup_failed" for item in cleanup.profiles))


if __name__ == "__main__":
    unittest.main()
