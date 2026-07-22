from __future__ import annotations

import os
import socket
import stat
import sys
import tempfile
import unittest
from pathlib import Path
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
            b"xapp-valid",
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

    def test_rejects_an_xapp_secret_crossing_the_streaming_chunk_boundary(self) -> None:
        home = self.write_profile("rick", ["SOUL.md"])
        token = b"xapp-1234567890-abcdefgh"
        (home / "SOUL.md").write_bytes(b"x" * (64 * 1024 - 3) + b"!" + token)
        scratch = self.root / "xapp-boundary-secret"
        scratch.mkdir(mode=0o700)

        with self.assertRaises(ProfileSnapshotError) as caught:
            prepare_profile_snapshots(self.manifest(self.profile("rick")), scratch, allow_missing=False)

        self.assertEqual(caught.exception.category, "invalid_local_profile")
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

    def test_rejects_group_or_world_accessible_scratch(self) -> None:
        home = self.write_profile("rick", ["SOUL.md"])
        (home / "SOUL.md").write_text("safe\n", encoding="utf-8")
        self.scratch.chmod(0o750)
        with self.assertRaises(ValueError):
            prepare_profile_snapshots(self.manifest(self.profile("rick")), self.scratch, allow_missing=False)

    def test_scratch_rename_and_symlink_swap_cannot_redirect_snapshot_writes(self) -> None:
        home = self.write_profile("rick", ["SOUL.md"])
        (home / "SOUL.md").write_text("safe\n", encoding="utf-8")
        scratch = self.root / "swap-scratch"
        scratch.mkdir(mode=0o700)
        moved = self.root / "moved-scratch"
        outside = self.root / "outside"
        outside.mkdir()
        original_fchmod = os.fchmod
        swapped = False

        def fchmod_then_swap(descriptor: int, mode: int) -> None:
            nonlocal swapped
            original_fchmod(descriptor, mode)
            if not swapped:
                swapped = True
                scratch.rename(moved)
                scratch.symlink_to(outside, target_is_directory=True)

        with mock.patch("hermes_bootstrap.profile_snapshot.os.fchmod", side_effect=fchmod_then_swap):
            with self.assertRaises(ProfileSnapshotError) as caught:
                prepare_profile_snapshots(self.manifest(self.profile("rick")), scratch, allow_missing=False)
        self.assertEqual(caught.exception.category, "invalid_local_profile")
        self.assertFalse((outside / "rick" / "SOUL.md").exists())
        self.assertFalse((moved / "rick").exists())

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

    def test_rejects_case_colliding_ancestors_and_control_name_variants(self) -> None:
        home = self.write_profile("rick", ["Assets/a.txt", "assets/b.txt"])
        (home / "Assets").mkdir()
        (home / "Assets" / "a.txt").write_text("one\n", encoding="utf-8")
        (home / "assets").mkdir()
        (home / "assets" / "b.txt").write_text("two\n", encoding="utf-8")
        with self.assertRaises(ProfileSnapshotError) as caught:
            prepare_profile_snapshots(self.manifest(self.profile("rick")), self.scratch, allow_missing=False)
        self.assertEqual(caught.exception.category, "invalid_local_profile")
        self.assertFalse((self.scratch / "rick").exists())

        for index, control in enumerate(("Distribution.yaml", ".GitIgnore")):
            with self.subTest(control=control):
                name = f"control{index}"
                profile_home = self.write_profile(name, [control])
                (profile_home / control).write_text("not a control file\n", encoding="utf-8")
                scratch = self.root / f"control-scratch-{index}"
                scratch.mkdir(mode=0o700)
                with self.assertRaises(ProfileSnapshotError) as control_error:
                    prepare_profile_snapshots(self.manifest(self.profile(name)), scratch, allow_missing=False)
                self.assertEqual(control_error.exception.category, "invalid_local_profile")
                self.assertEqual(list(scratch.iterdir()), [])

    def test_rejects_git_metadata_names_at_any_depth(self) -> None:
        for index, control in enumerate((".git", ".gitignore", ".gitattributes", ".gitmodules")):
            with self.subTest(control=control):
                name = f"nested{index}"
                home = self.write_profile(name, ["assets"])
                nested = home / "assets" / "nested"
                nested.mkdir(parents=True)
                candidate = nested / control
                if control == ".git":
                    candidate.mkdir()
                    (candidate / "config").write_text("[core]\n", encoding="utf-8")
                else:
                    candidate.write_text("unsafe\n", encoding="utf-8")
                scratch = self.root / f"nested-control-{index}"
                scratch.mkdir(mode=0o700)
                with self.assertRaises(ProfileSnapshotError) as caught:
                    prepare_profile_snapshots(self.manifest(self.profile(name)), scratch, allow_missing=False)
                self.assertEqual(caught.exception.category, "invalid_local_profile")
                self.assertEqual(list(scratch.iterdir()), [])

    def test_rejects_a_hardlink_created_while_streaming(self) -> None:
        home = self.write_profile("rick", ["SOUL.md"])
        content = b"link-during-copy\n"
        source = home / "SOUL.md"
        source.write_bytes(content)
        external_link = self.root / "late-hardlink"
        original_write = profile_snapshot._write_descriptor
        linked = False

        def write_then_link(descriptor: int, chunk: bytes) -> None:
            nonlocal linked
            original_write(descriptor, chunk)
            if chunk == content and not linked:
                os.link(source, external_link)
                linked = True

        with mock.patch("hermes_bootstrap.profile_snapshot._write_descriptor", side_effect=write_then_link):
            with self.assertRaises(ProfileSnapshotError) as caught:
                prepare_profile_snapshots(self.manifest(self.profile("rick")), self.scratch, allow_missing=False)
        self.assertTrue(linked)
        self.assertEqual(caught.exception.category, "invalid_local_profile")
        self.assertFalse((self.scratch / "rick").exists())

    def test_rejects_same_uid_destination_replacement_before_return(self) -> None:
        home = self.write_profile("rick", ["SOUL.md"])
        content = b"canonical-snapshot-content\n"
        (home / "SOUL.md").write_bytes(content)
        replacement = self.root / "destination-replacement"
        replacement.write_bytes(b"altered-after-copy\n")
        original_write = profile_snapshot._write_descriptor
        replaced = False

        def write_then_replace(descriptor: int, chunk: bytes) -> None:
            nonlocal replaced
            original_write(descriptor, chunk)
            if chunk == content and not replaced:
                os.replace(replacement, self.scratch / "rick" / "SOUL.md")
                replaced = True

        with mock.patch("hermes_bootstrap.profile_snapshot._write_descriptor", side_effect=write_then_replace):
            with self.assertRaises(ProfileSnapshotError) as caught:
                prepare_profile_snapshots(self.manifest(self.profile("rick")), self.scratch, allow_missing=False)
        self.assertTrue(replaced)
        self.assertEqual(caught.exception.category, "invalid_local_profile")
        self.assertFalse((self.scratch / "rick").exists())

    def test_rejects_gitignore_destination_replacement_before_return(self) -> None:
        home = self.write_profile("rick", ["SOUL.md"])
        (home / "SOUL.md").write_text("safe\n", encoding="utf-8")
        replacement = self.root / "gitignore-replacement"
        replacement.write_bytes(b"*\n")
        replacement.chmod(0o644)
        original_write = profile_snapshot._write_private_file_at
        replaced = False

        def write_then_replace(parent_fd: int, name: str, content: bytes, mode: int):
            nonlocal replaced
            result = original_write(parent_fd, name, content, mode)
            if name == ".gitignore" and not replaced:
                os.replace(replacement, self.scratch / "rick" / name)
                replaced = True
            return result

        with mock.patch("hermes_bootstrap.profile_snapshot._write_private_file_at", side_effect=write_then_replace):
            with self.assertRaises(ProfileSnapshotError) as caught:
                prepare_profile_snapshots(self.manifest(self.profile("rick")), self.scratch, allow_missing=False)
        self.assertTrue(replaced)
        self.assertEqual(caught.exception.category, "invalid_local_profile")
        self.assertFalse((self.scratch / "rick").exists())

    def test_output_root_rename_cleanup_removes_exact_tree_and_preserves_replacement(self) -> None:
        home = self.write_profile("rick", ["SOUL.md"])
        content = b"rename-output-root\n"
        (home / "SOUL.md").write_bytes(content)
        moved = self.scratch / "retired-rick"
        replacement = self.scratch / "rick"
        original_write = profile_snapshot._write_descriptor
        swapped = False

        def write_then_swap(descriptor: int, chunk: bytes) -> None:
            nonlocal swapped
            original_write(descriptor, chunk)
            if chunk == content and not swapped:
                (self.scratch / "rick").rename(moved)
                replacement.mkdir(mode=0o700)
                (replacement / "marker").write_text("replacement\n", encoding="utf-8")
                swapped = True

        with mock.patch("hermes_bootstrap.profile_snapshot._write_descriptor", side_effect=write_then_swap):
            with self.assertRaises(ProfileSnapshotError) as caught:
                prepare_profile_snapshots(self.manifest(self.profile("rick")), self.scratch, allow_missing=False)
        self.assertTrue(swapped)
        self.assertEqual(caught.exception.category, "invalid_local_profile")
        self.assertFalse(moved.exists())
        self.assertEqual((replacement / "marker").read_text(encoding="utf-8"), "replacement\n")

    def test_output_root_cleanup_failure_is_redacted_and_surfaced(self) -> None:
        home = self.write_profile("rick", ["SOUL.md"])
        content = b"escape-output-root\n"
        (home / "SOUL.md").write_bytes(content)
        escaped = self.root / "escaped-rick"
        replacement = self.scratch / "rick"
        original_write = profile_snapshot._write_descriptor
        swapped = False

        def write_then_escape(descriptor: int, chunk: bytes) -> None:
            nonlocal swapped
            original_write(descriptor, chunk)
            if chunk == content and not swapped:
                (self.scratch / "rick").rename(escaped)
                replacement.mkdir(mode=0o700)
                (replacement / "marker").write_text("replacement\n", encoding="utf-8")
                swapped = True

        with mock.patch("hermes_bootstrap.profile_snapshot._write_descriptor", side_effect=write_then_escape):
            with self.assertRaises(ProfileSnapshotError) as caught:
                prepare_profile_snapshots(self.manifest(self.profile("rick")), self.scratch, allow_missing=False)
        self.assertTrue(swapped)
        self.assertEqual(caught.exception.category, "cleanup_failed")
        self.assertEqual((replacement / "marker").read_text(encoding="utf-8"), "replacement\n")
        self.assertTrue(escaped.is_dir())
        self.assertEqual(list(escaped.iterdir()), [])

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

    def test_real_nested_directory_replacement_is_rejected_and_cleaned_up(self) -> None:
        home = self.write_profile("rick", ["assets"])
        nested = home / "assets" / "nested"
        nested.mkdir(parents=True)
        (nested / "avatar.png").write_bytes(b"nested-avatar")
        replacement = self.root / "replacement-assets"
        replacement.mkdir()
        (replacement / "replacement.png").write_bytes(b"replacement")
        original_write = profile_snapshot._write_descriptor
        replaced = False

        def write_then_replace_nested(directory: int, content: bytes) -> None:
            nonlocal replaced
            original_write(directory, content)
            if content == b"nested-avatar" and not replaced:
                replaced = True
                os.replace(home / "assets", self.root / "stale-assets")
                os.replace(replacement, home / "assets")

        with mock.patch("hermes_bootstrap.profile_snapshot._write_descriptor", side_effect=write_then_replace_nested):
            with self.assertRaises(ProfileSnapshotError) as caught:
                prepare_profile_snapshots(self.manifest(self.profile("rick")), self.scratch, allow_missing=False)
        self.assertEqual(caught.exception.category, "invalid_local_profile")
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
        source_stat = home.stat()
        replaced = False

        def read_then_replace(parent_fd: int, name: str):
            nonlocal replaced
            result = original_read(parent_fd, name)
            if name == "distribution.yaml" and os.fstat(parent_fd).st_ino == source_stat.st_ino and not replaced:
                replaced = True
                os.replace(replacement, home / "distribution.yaml")
            return result

        with mock.patch("hermes_bootstrap.profile_snapshot._read_regular", side_effect=read_then_replace):
            with self.assertRaises(ProfileSnapshotError) as caught:
                prepare_profile_snapshots(self.manifest(self.profile("rick")), self.scratch, allow_missing=False)
        self.assertTrue(replaced)
        self.assertEqual(caught.exception.category, "invalid_local_profile")
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
        original_read = profile_snapshot.distributions._read_profile_manifest_at
        calls: list[bool] = []
        replaced = False

        def read_then_replace(root: Path, expected_name: str, *, require_sources: bool):
            nonlocal replaced
            calls.append(require_sources)
            result = original_read(root, expected_name, require_sources=require_sources)
            os.replace(replacement, root / "distribution.yaml")
            replaced = True
            return result

        with mock.patch.object(profile_snapshot.distributions, "_read_profile_manifest_at", side_effect=read_then_replace):
            with self.assertRaises(ProfileSnapshotError) as caught:
                prepare_profile_snapshots(self.manifest(self.profile("rick")), self.scratch, allow_missing=False)
        self.assertTrue(replaced)
        self.assertEqual(calls, [True])
        self.assertEqual(caught.exception.category, "invalid_local_profile")
        self.assertFalse((self.scratch / "rick").exists())

    def test_rejects_incompatible_hermes_requirement(self) -> None:
        home = self.write_profile("rick", ["SOUL.md"])
        (home / "SOUL.md").write_text("safe\n", encoding="utf-8")
        (home / "distribution.yaml").write_text(
            yaml.safe_dump({"name": "rick", "version": "0.1.0", "hermes_requires": ">999.0.0", "distribution_owned": ["SOUL.md"]}),
            encoding="utf-8",
        )
        with self.assertRaises(ProfileSnapshotError):
            prepare_profile_snapshots(self.manifest(self.profile("rick")), self.scratch, allow_missing=False)


if __name__ == "__main__":
    unittest.main()
