from __future__ import annotations

import os
import socket
import stat
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

import yaml


BOOTSTRAP_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BOOTSTRAP_ROOT))

from hermes_bootstrap.models import BootstrapManifest, DistributionSource
from hermes_bootstrap import profile_snapshot
from hermes_bootstrap.profile_snapshot import ProfileSnapshotError, prepare_profile_snapshots


class ProfileSnapshotTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.data_root = self.root / "data"
        self.data_root.mkdir()
        self.scratch = self.root / "scratch"
        self.scratch.mkdir(mode=0o700)

    def profile(self, name: str) -> DistributionSource:
        return DistributionSource(
            name,
            f"https://github.com/rurusasu/hermes-profile-{name}.git",
            "main",
            self.data_root / "profiles" / name,
            "distribution.yaml",
        )

    def manifest(self, *profiles: DistributionSource) -> BootstrapManifest:
        root = DistributionSource(
            "default", "https://github.com/rurusasu/hermes-home.git", "main", self.data_root, "root-distribution.yaml"
        )
        return BootstrapManifest(1, self.data_root, (), root, profiles, ())

    def write_profile(self, name: str, owned: list[str], **overrides: object) -> Path:
        home = self.profile(name).target
        home.mkdir(parents=True, exist_ok=True)
        payload: dict[str, object] = {
            "name": name,
            "version": "0.1.0",
            "hermes_requires": ">=0.18.2",
            "distribution_owned": owned,
        }
        payload.update(overrides)
        (home / "distribution.yaml").write_text(yaml.safe_dump(payload, sort_keys=False), encoding="utf-8")
        return home

    def prepare(self, name: str, *, owned: list[str], **overrides: object):
        home = self.write_profile(name, owned, **overrides)
        for item in owned:
            path = home / item
            if item.endswith("/") or item == "assets" or item.startswith("assets/"):
                path.mkdir(parents=True, exist_ok=True)
            elif not path.exists():
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b"safe\n")
        prepared = prepare_profile_snapshots(self.manifest(self.profile(name)), self.scratch, allow_missing=False)
        return prepared.snapshots[0]

    def test_canonical_manifest_strips_runtime_fields_and_rejects_unknown_keys(self) -> None:
        snapshot = self.prepare(
            "rick",
            owned=["SOUL.md", "assets"],
            description="A canonical profile",
            author="Rick Sanchez",
            license="MIT",
            env_requires=[{"name": "RICK_PORTAL", "description": "Portal fluid", "required": False}],
            source="https://example.invalid/ignored.git",
            installed_at="2026-07-23T00:00:00Z",
        )
        payload = yaml.safe_load(snapshot.manifest_bytes)
        self.assertNotIn("source", payload)
        self.assertNotIn("installed_at", payload)
        self.assertEqual(payload["distribution_owned"], ["SOUL.md", "assets"])
        self.assertEqual(tuple(payload), ("name", "version", "description", "hermes_requires", "author", "license", "env_requires", "distribution_owned"))

        home = self.profile("rick").target
        payload["unknown"] = "nope"
        (home / "distribution.yaml").write_text(yaml.safe_dump(payload, sort_keys=False), encoding="utf-8")
        clean_scratch = self.root / "unknown-key"
        clean_scratch.mkdir(mode=0o700)
        with self.assertRaises(ProfileSnapshotError):
            prepare_profile_snapshots(self.manifest(self.profile("rick")), clean_scratch, allow_missing=False)

    def test_gitignore_is_an_exact_root_allowlist_with_nested_parents(self) -> None:
        snapshot = self.prepare("rick", owned=["SOUL.md", "assets/icons"])
        self.assertEqual(
            snapshot.gitignore_bytes.decode("ascii").splitlines(),
            [
                "/*", "!/.gitignore", "!/distribution.yaml", "!/SOUL.md",
                "!/assets/", "!/assets/icons/", "!/assets/icons/**",
            ],
        )

    def test_manifest_rejects_duplicate_identity_empty_overlap_and_nonportable_ownership(self) -> None:
        home = self.write_profile("rick", ["SOUL.md"])
        (home / "SOUL.md").write_text("safe\n", encoding="utf-8")
        invalid = (
            "name: rick\nname: duplicate\nversion: 0.1.0\nhermes_requires: '>=0.18.2'\ndistribution_owned: [SOUL.md]\n",
            yaml.safe_dump({"name": "hoffman", "version": "0.1.0", "hermes_requires": ">=0.18.2", "distribution_owned": ["SOUL.md"]}),
            yaml.safe_dump({"name": "rick", "version": "0.1.0", "hermes_requires": ">=0.18.2", "distribution_owned": []}),
            yaml.safe_dump({"name": "rick", "version": "0.1.0", "hermes_requires": ">=0.18.2", "distribution_owned": ["assets", "assets/icon.png"]}),
            yaml.safe_dump({"name": "rick", "version": "0.1.0", "hermes_requires": ">=0.18.2", "distribution_owned": ["bad:name"]}),
            yaml.safe_dump({"name": "rick", "version": "0.1.0", "hermes_requires": ">=0.18.2", "distribution_owned": [".gitignore"]}),
            yaml.safe_dump({"name": "rick", "version": "0.1.0", "hermes_requires": ">=0.18.2", "distribution_owned": ["distribution.yaml"]}),
        )
        for content in invalid:
            with self.subTest(content=content):
                (home / "distribution.yaml").write_text(content, encoding="utf-8")
                with self.assertRaises(ProfileSnapshotError):
                    prepare_profile_snapshots(self.manifest(self.profile("rick")), self.scratch, allow_missing=False)

    def test_rejects_reserved_paths_and_secret_candidates(self) -> None:
        for unsafe in (
            ".env", "auth.json", ".git/config", "memories", "sessions", "logs",
            "plans", "workspace", "home", "cron/output", "cron/state", "locks",
        ):
            with self.subTest(unsafe=unsafe), self.assertRaises(ProfileSnapshotError):
                self.prepare("rick", owned=[unsafe])

        for index, content in enumerate((
            b"ghp_abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN",
            b"xoxb-1234567890-abcdefgh",
            b"-----BEGIN PRIVATE KEY-----",
        )):
            with self.subTest(content=content), self.assertRaises(ProfileSnapshotError):
                home = self.write_profile("rick", ["SOUL.md"])
                (home / "SOUL.md").write_bytes(content)
                scratch = self.root / f"secret-{index}"
                scratch.mkdir(mode=0o700)
                prepare_profile_snapshots(self.manifest(self.profile("rick")), scratch, allow_missing=False)

    def test_rejects_a_secret_crossing_the_streaming_chunk_boundary(self) -> None:
        home = self.write_profile("rick", ["SOUL.md"])
        token = b"ghp_abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN"
        (home / "SOUL.md").write_bytes(b"x" * (64 * 1024 - 5) + b"!" + token)
        scratch = self.root / "boundary-secret"
        scratch.mkdir(mode=0o700)

        with mock.patch.object(profile_snapshot, "_reject_sensitive_bytes", wraps=profile_snapshot._reject_sensitive_bytes) as reject:
            with self.assertRaises(ProfileSnapshotError):
                prepare_profile_snapshots(self.manifest(self.profile("rick")), scratch, allow_missing=False)

        self.assertGreater(reject.call_count, 2)
        self.assertFalse((scratch / "rick").exists())

    def test_accepts_an_owned_file_larger_than_sixteen_mebibytes(self) -> None:
        home = self.write_profile("rick", ["archive.bin"])
        large = home / "archive.bin"
        with large.open("wb") as handle:
            handle.seek(16 * 1024 * 1024)
            handle.write(b"\0")
        scratch = self.root / "large-file"
        scratch.mkdir(mode=0o700)

        snapshot = prepare_profile_snapshots(self.manifest(self.profile("rick")), scratch, allow_missing=False).snapshots[0]

        self.assertEqual(snapshot.entries[0].size, 16 * 1024 * 1024 + 1)
        self.assertEqual((snapshot.root / "archive.bin").stat().st_size, 16 * 1024 * 1024 + 1)

    def test_rejects_links_special_files_hardlinks_and_unreadable_files(self) -> None:
        home = self.write_profile("rick", ["assets"])
        (home / "assets").mkdir()
        (home / "assets" / "link").symlink_to("elsewhere")
        with self.assertRaises(ProfileSnapshotError):
            prepare_profile_snapshots(self.manifest(self.profile("rick")), self.scratch, allow_missing=False)

        for kind in ("fifo", "socket", "hardlink", "unreadable"):
            with self.subTest(kind=kind):
                for child in (home / "assets").iterdir():
                    child.unlink()
                path = home / "assets" / kind
                if kind == "fifo":
                    os.mkfifo(path)
                elif kind == "socket":
                    server = socket.socket(socket.AF_UNIX)
                    self.addCleanup(server.close)
                    server.bind(str(path))
                else:
                    path.write_text("safe\n", encoding="utf-8")
                    if kind == "hardlink":
                        os.link(path, home / "extra-link")
                    else:
                        path.chmod(0)
                with self.assertRaises(ProfileSnapshotError):
                    prepare_profile_snapshots(self.manifest(self.profile("rick")), self.scratch, allow_missing=False)
                if kind == "unreadable":
                    path.chmod(0o600)
                if kind == "hardlink":
                    (home / "extra-link").unlink()

    def test_snapshot_is_deterministic_and_contains_only_owned_projection(self) -> None:
        rick = self.write_profile("rick", ["assets", "SOUL.md"])
        (rick / "SOUL.md").write_text("Rick\n", encoding="utf-8")
        (rick / "assets").mkdir()
        (rick / "assets" / "avatar.png").write_bytes(b"rick-avatar")
        (rick / "unowned.txt").write_text("not mirrored\n", encoding="utf-8")
        hoffman = self.write_profile("hoffman", ["portfolio.pdf"])
        (hoffman / "portfolio.pdf").write_bytes(b"hoffman-portfolio")
        risa = self.write_profile("risarisa", ["SOUL.md"])
        (risa / "SOUL.md").write_text("RisaRisa\n", encoding="utf-8")

        prepared = prepare_profile_snapshots(
            self.manifest(self.profile("rick"), self.profile("hoffman"), self.profile("risarisa")), self.scratch, allow_missing=False
        )
        snapshots = {snapshot.declaration.name: snapshot for snapshot in prepared.snapshots}
        self.assertEqual([entry.path.as_posix() for entry in snapshots["rick"].entries], ["SOUL.md", "assets/avatar.png"])
        self.assertEqual([entry.path.as_posix() for entry in snapshots["hoffman"].entries], ["portfolio.pdf"])
        self.assertNotIn("assets", [entry.path.parts[0] for entry in snapshots["risarisa"].entries])
        self.assertEqual(sorted(path.relative_to(snapshots["rick"].root).as_posix() for path in snapshots["rick"].root.rglob("*") if path.is_file()), [".gitignore", "SOUL.md", "assets/avatar.png", "distribution.yaml"])
        again_root = self.root / "again"
        again_root.mkdir(mode=0o700)
        again = prepare_profile_snapshots(self.manifest(self.profile("rick")), again_root, allow_missing=False)
        self.assertEqual(snapshots["rick"].digest, again.snapshots[0].digest)

    def test_missing_profiles_are_reported_only_when_allowed(self) -> None:
        profile = self.profile("rick")
        self.assertEqual(prepare_profile_snapshots(self.manifest(profile), self.scratch, allow_missing=True).missing, (profile,))
        with self.assertRaises(ProfileSnapshotError):
            prepare_profile_snapshots(self.manifest(profile), self.scratch, allow_missing=False)

    def test_rejects_profile_names_that_cannot_be_safe_scratch_components(self) -> None:
        for index, name in enumerate(("../outside", "rick/morty", r"rick\morty", ".", "..", "Rick", "rick_", "rick.", "rick ")):
            with self.subTest(name=name):
                target = self.data_root / "profiles" / name
                target.mkdir(parents=True, exist_ok=True)
                (target / "distribution.yaml").write_text(
                    yaml.safe_dump(
                        {"name": name, "version": "0.1.0", "hermes_requires": ">=0.18.2", "distribution_owned": ["SOUL.md"]},
                        sort_keys=False,
                    ),
                    encoding="utf-8",
                )
                (target / "SOUL.md").write_text("safe\n", encoding="utf-8")
                declaration = DistributionSource(name, "https://github.com/rurusasu/hermes-profile-rick.git", "main", target, "distribution.yaml")
                scratch = self.root / f"unsafe-name-{index}"
                scratch.mkdir(mode=0o700)
                with self.assertRaises(ProfileSnapshotError):
                    prepare_profile_snapshots(self.manifest(declaration), scratch, allow_missing=False)
                self.assertFalse((self.root / "outside").exists())
                self.assertEqual(list(scratch.iterdir()), [])

    def test_rejects_an_external_target_and_preserves_executable_git_mode(self) -> None:
        home = self.write_profile("rick", ["tools/sync"])
        executable = home / "tools" / "sync"
        executable.parent.mkdir()
        executable.write_text("#!/bin/sh\n", encoding="utf-8")
        executable.chmod(0o755)
        snapshot = prepare_profile_snapshots(self.manifest(self.profile("rick")), self.scratch, allow_missing=False).snapshots[0]
        self.assertEqual(snapshot.entries[0].mode, 0o755)
        self.assertEqual(stat.S_IMODE((snapshot.root / "tools" / "sync").stat().st_mode), 0o755)

        external = DistributionSource("rick", "https://github.com/rurusasu/hermes-profile-rick.git", "main", self.root / "outside", "distribution.yaml")
        external_scratch = self.root / "external"
        external_scratch.mkdir(mode=0o700)
        with self.assertRaises(ProfileSnapshotError):
            prepare_profile_snapshots(self.manifest(external), external_scratch, allow_missing=False)

    def test_case_collision_and_real_file_replacement_are_rejected_and_cleaned_up(self) -> None:
        home = self.write_profile("rick", ["assets"])
        (home / "assets").mkdir()
        (home / "assets" / "Avatar.png").write_bytes(b"one")
        (home / "assets" / "avatar.png").write_bytes(b"two")
        with self.assertRaises(ProfileSnapshotError):
            prepare_profile_snapshots(self.manifest(self.profile("rick")), self.scratch, allow_missing=False)
        self.assertFalse((self.scratch / "rick").exists())

        (home / "assets" / "avatar.png").unlink()
        replacement = self.root / "replacement.txt"
        replacement.write_text("replacement\n", encoding="utf-8")
        original_write = profile_snapshot._write_descriptor

        def write_then_replace(descriptor: int, content: bytes) -> None:
            original_write(descriptor, content)
            if content == b"one":
                os.replace(replacement, home / "assets" / "Avatar.png")

        with mock.patch("hermes_bootstrap.profile_snapshot._write_descriptor", side_effect=write_then_replace):
            with self.assertRaises(ProfileSnapshotError):
                prepare_profile_snapshots(self.manifest(self.profile("rick")), self.scratch, allow_missing=False)
        self.assertFalse((self.scratch / "rick").exists())

    def test_real_directory_ancestor_replacement_is_detected_before_a_snapshot_escapes(self) -> None:
        home = self.write_profile("rick", ["SOUL.md"])
        (home / "SOUL.md").write_text("safe\n", encoding="utf-8")
        profiles = home.parent
        moved = self.root / "moved-profiles"
        original_write = profile_snapshot._write_descriptor

        def write_then_swap(descriptor: int, content: bytes) -> None:
            original_write(descriptor, content)
            profiles.rename(moved)
            profiles.mkdir()
            (profiles / "rick").mkdir()

        with mock.patch("hermes_bootstrap.profile_snapshot._write_descriptor", side_effect=write_then_swap):
            with self.assertRaises(ProfileSnapshotError):
                prepare_profile_snapshots(self.manifest(self.profile("rick")), self.scratch, allow_missing=False)
        self.assertFalse((self.scratch / "rick").exists())

    def test_rejects_a_manifest_replaced_after_descriptor_read(self) -> None:
        home = self.write_profile("rick", ["SOUL.md"], description="original")
        (home / "SOUL.md").write_text("safe\n", encoding="utf-8")
        replacement = self.root / "replacement-manifest.yaml"
        replacement.write_text(
            yaml.safe_dump(
                {"name": "rick", "version": "0.1.0", "description": "replaced", "hermes_requires": ">=0.18.2", "distribution_owned": ["SOUL.md"]},
                sort_keys=False,
            ),
            encoding="utf-8",
        )
        original_read = profile_snapshot._read_regular

        def read_then_replace(parent_fd: int, name: str):
            result = original_read(parent_fd, name)
            if name == "distribution.yaml":
                os.replace(replacement, home / "distribution.yaml")
            return result

        with mock.patch("hermes_bootstrap.profile_snapshot._read_regular", side_effect=read_then_replace):
            with self.assertRaises(ProfileSnapshotError):
                prepare_profile_snapshots(self.manifest(self.profile("rick")), self.scratch, allow_missing=False)
        self.assertFalse((self.scratch / "rick").exists())

    def test_rejects_private_manifest_replaced_during_hermes_validation(self) -> None:
        home = self.write_profile("rick", ["SOUL.md"], description="original")
        (home / "SOUL.md").write_text("safe\n", encoding="utf-8")
        replacement = self.root / "private-replacement.yaml"
        replacement.write_text(
            yaml.safe_dump(
                {"name": "rick", "version": "0.1.0", "description": "replaced", "hermes_requires": ">=0.18.2", "distribution_owned": ["SOUL.md"]},
                sort_keys=False,
            ),
            encoding="utf-8",
        )
        original_validate = profile_snapshot.distributions._read_profile_manifest_at

        def validate_then_replace(root: Path, expected_name: str, *, require_sources: bool):
            result = original_validate(root, expected_name, require_sources=require_sources)
            if root != home:
                os.replace(replacement, root / "distribution.yaml")
            return result

        with mock.patch("hermes_bootstrap.profile_snapshot.distributions._read_profile_manifest_at", side_effect=validate_then_replace):
            with self.assertRaises(ProfileSnapshotError):
                prepare_profile_snapshots(self.manifest(self.profile("rick")), self.scratch, allow_missing=False)
        self.assertFalse((self.scratch / "rick").exists())

    def test_rejects_a_manifest_that_changes_after_hermes_compatibility_validation(self) -> None:
        home = self.write_profile("rick", ["SOUL.md"])
        (home / "SOUL.md").write_text("safe\n", encoding="utf-8")
        parsed = SimpleNamespace(name="rick", version="0.1.0", hermes_requires=">999.0.0")
        with mock.patch("hermes_bootstrap.profile_snapshot.distributions._read_profile_manifest_at", return_value=(parsed, ())):
            with self.assertRaises(ProfileSnapshotError):
                prepare_profile_snapshots(self.manifest(self.profile("rick")), self.scratch, allow_missing=False)


if __name__ == "__main__":
    unittest.main()
