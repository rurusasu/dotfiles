"""Runtime contracts for mandatory producer-to-E2E artifacts."""

from __future__ import annotations

import base64
import copy
import hashlib
import io
import json
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import prepare_ci_nix_artifact as artifact
from prepare_ci_nix_cache import narinfo

SOURCE = "/nix/store/" + "a" * 32 + "-source"
PUBLIC = "/nix/store/" + "b" * 32 + "-public"
SYSTEM = "/nix/store/" + "c" * 32 + "-system"
TESTED_SHA = "d" * 40
LOCK_DIGEST = "e" * 64
NAR_HASH = "sha256-" + base64.b64encode(bytes(32)).decode()


class ArtifactTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.metadata = {
            SOURCE: {"path": SOURCE, "narHash": NAR_HASH, "narSize": 41, "references": [PUBLIC]},
            PUBLIC: {"path": PUBLIC, "narHash": NAR_HASH, "narSize": 42, "references": []},
            SYSTEM: {"path": SYSTEM, "narHash": NAR_HASH, "narSize": 43, "references": [SOURCE, PUBLIC]},
        }
        self.manifest = {
            "schemaVersion": 1,
            "target": "wsl",
            "testedSha": TESTED_SHA,
            "roots": {"source": SOURCE, "system": SYSTEM},
            "source": {"path": SOURCE, "narHash": NAR_HASH, "flakeLockSha256": LOCK_DIGEST},
            "closure": list(self.metadata.values()),
            "publicPaths": [PUBLIC],
            "archiveSha256": "f" * 64,
        }
        self.cache = self.directory / "staging" / "cache"
        (self.cache / "nar").mkdir(parents=True)
        (self.cache / "nix-cache-info").write_text("StoreDir: /nix/store\n")
        for path in (SOURCE, SYSTEM):
            self.add_entry(path)
        self.pack()

    def add_entry(self, path):
        payload = path.encode()
        digest = hashlib.sha256(payload).digest()
        filename = digest.hex() + ".nar.zst"
        blob = self.cache / "nar" / filename
        blob.write_bytes(payload)
        info = self.cache / (Path(path).name.split("-", 1)[0] + ".narinfo")
        info.write_text(narinfo(self.metadata[path], filename, len(payload), base64.b64encode(digest).decode()))

    def pack(self):
        with tarfile.open(self.directory / "closure.tar", "w") as stream:
            stream.add(self.cache, arcname="cache")
        self.manifest["archiveSha256"] = artifact.sha256(self.directory / "closure.tar")
        self.write_manifest()

    def write_manifest(self):
        (self.directory / "manifest.json").write_text(json.dumps(self.manifest))

    def import_fixture(self):
        original_is_file = Path.is_file
        original_sha256 = artifact.sha256
        lock = Path(SOURCE) / "flake.lock"
        with (
            patch.object(Path, "is_file", lambda path: path == lock or original_is_file(path)),
            patch.object(artifact, "sha256", lambda path: LOCK_DIGEST if path == lock else original_sha256(path)),
            patch.object(artifact, "closure_metadata", return_value=self.metadata),
            patch.object(artifact.subprocess, "run") as commands,
        ):
            roots = artifact.import_artifact("wsl", TESTED_SHA, self.directory)
        return roots, commands

    def assert_rejected_without_nix(self, expected=ValueError):
        with patch.object(artifact.subprocess, "run") as commands:
            with self.assertRaises(expected):
                artifact.import_artifact("wsl", TESTED_SHA, self.directory)
            commands.assert_not_called()

    def test_complete_artifact_prefetches_public_then_imports_exact_roots_without_builds(self):
        roots, commands = self.import_fixture()
        self.assertEqual(roots, self.manifest["roots"])
        calls = commands.call_args_list
        self.assertEqual(len(calls), 2)
        self.assertEqual(calls[0].args[0], ["nix-store", *artifact.NO_BUILD, "--realise", PUBLIC])
        self.assertEqual(calls[1].args[0][:1], ["nix"])
        self.assertIn("--no-check-sigs", calls[1].args[0])
        self.assertEqual(calls[1].kwargs["input"], SOURCE + "\n" + SYSTEM + "\n")
        self.assertEqual(json.loads((self.directory / "roots.json").read_text()), roots)
        self.assertIn("CI_ARTIFACT_ROOT_SOURCE=", (self.directory / "roots.env").read_text())

    def test_wrong_target_and_sha_are_rejected_before_nix(self):
        for field, value in (("target", "darwin"), ("testedSha", "1" * 40)):
            with self.subTest(field=field):
                original = self.manifest[field]
                self.manifest[field] = value
                self.write_manifest()
                self.assert_rejected_without_nix()
                self.manifest[field] = original

    def test_empty_roots_and_missing_source_are_rejected(self):
        for roots in ({}, {"system": SYSTEM}):
            with self.subTest(roots=roots):
                self.manifest["roots"] = roots
                self.write_manifest()
                self.assert_rejected_without_nix()

    def test_archive_tampering_is_rejected_before_nix(self):
        with (self.directory / "closure.tar").open("ab") as stream:
            stream.write(b"tampering")
        self.assert_rejected_without_nix()

    def test_missing_private_payload_is_rejected_before_nix(self):
        next((self.cache / "nar").iterdir()).unlink()
        self.pack()
        self.assert_rejected_without_nix()

    def test_payload_hash_is_checked_before_nix(self):
        next((self.cache / "nar").iterdir()).write_bytes(b"corrupt")
        self.pack()
        self.assert_rejected_without_nix()

    def test_unknown_private_reference_and_nonclosed_public_set_are_rejected(self):
        for reference in (SOURCE, "/nix/store/" + "f" * 32 + "-unknown"):
            with self.subTest(reference=reference):
                manifest = copy.deepcopy(self.manifest)
                manifest["closure"][1]["references"] = [reference]
                (self.directory / "manifest.json").write_text(json.dumps(manifest))
                self.assert_rejected_without_nix()

    def test_tar_traversal_and_links_are_rejected_before_nix(self):
        for name, kind in (("cache/../../escape", tarfile.REGTYPE), ("cache/link", tarfile.SYMTYPE)):
            with self.subTest(name=name):
                with tarfile.open(self.directory / "closure.tar", "w") as stream:
                    member = tarfile.TarInfo(name)
                    member.type = kind
                    if kind == tarfile.SYMTYPE:
                        member.linkname = "/tmp/escape"
                    stream.addfile(member, io.BytesIO())
                self.manifest["archiveSha256"] = artifact.sha256(self.directory / "closure.tar")
                self.write_manifest()
                self.assert_rejected_without_nix()

    def test_duplicate_json_keys_are_rejected(self):
        (self.directory / "manifest.json").write_text('{"target":"wsl","target":"darwin"}')
        self.assert_rejected_without_nix()

    def test_imported_closure_must_match_producer(self):
        original_is_file = Path.is_file
        original_sha256 = artifact.sha256
        lock = Path(SOURCE) / "flake.lock"
        changed = copy.deepcopy(self.metadata)
        changed[SYSTEM]["narSize"] += 1
        with (
            patch.object(Path, "is_file", lambda path: path == lock or original_is_file(path)),
            patch.object(artifact, "sha256", lambda path: LOCK_DIGEST if path == lock else original_sha256(path)),
            patch.object(artifact, "closure_metadata", return_value=changed),
            patch.object(artifact.subprocess, "run"),
        ):
            with self.assertRaisesRegex(ValueError, "Imported closure identity"):
                artifact.import_artifact("wsl", TESTED_SHA, self.directory)
        self.assertFalse((self.directory / "roots.json").exists())

    def test_source_checkout_lock_must_match_before_nix(self):
        source = self.directory / "checkout"
        source.mkdir()
        (source / "flake.lock").write_text("wrong lock")
        with patch.object(artifact.subprocess, "run") as commands:
            with self.assertRaisesRegex(ValueError, "Checkout lock"):
                artifact.import_artifact("wsl", TESTED_SHA, self.directory, source)
            commands.assert_not_called()

    def test_roots_arguments_reject_duplicate_invalid_and_missing_source(self):
        for arguments in ([], ["source=relative"], [f"source={SOURCE}", f"source={SOURCE}"], [f"SOURCE={SOURCE}"]):
            with self.subTest(arguments=arguments), self.assertRaises(ValueError):
                artifact.roots_from_arguments(arguments)

    def test_export_transfers_every_nonpublic_path_and_captures_source_identity(self):
        output = self.directory / "export"
        lock = Path(SOURCE) / "flake.lock"
        original_is_file = Path.is_file
        original_sha256 = artifact.sha256

        def export_entry(cache, path, metadata, maximum, timeout):
            self.assertGreater(maximum, 0)
            self.assertEqual(timeout, 600)
            self.assertEqual(list((cache / "nar").iterdir()), [])
            payload = path.encode()
            digest = hashlib.sha256(payload).digest()
            filename = digest.hex() + ".nar.zst"
            blob = cache / "nar" / filename
            blob.write_bytes(payload)
            info = cache / (Path(path).name.split("-", 1)[0] + ".narinfo")
            info.write_text(narinfo(metadata, filename, len(payload), base64.b64encode(digest).decode()))
            return info, blob, len(payload)

        roots = {**self.manifest["roots"], "python": PUBLIC}
        with (
            patch.object(Path, "is_file", lambda path: path == lock or original_is_file(path)),
            patch.object(artifact, "sha256", lambda path: LOCK_DIGEST if path == lock else original_sha256(path)),
            patch.object(artifact, "closure_metadata", return_value=self.metadata),
            patch.object(artifact, "query_public_paths", return_value={PUBLIC}),
            patch.object(artifact, "export_entry", side_effect=export_entry) as exporter,
        ):
            artifact.export_artifact("wsl", TESTED_SHA, roots, Path(SOURCE), output)
        self.assertEqual([call.args[1] for call in exporter.call_args_list], [SOURCE, SYSTEM])
        manifest = artifact.read_json(output / "manifest.json")
        self.assertEqual(manifest["source"]["flakeLockSha256"], LOCK_DIGEST)
        self.assertEqual(manifest["publicPaths"], [PUBLIC])
        self.assertEqual(manifest["roots"]["python"], PUBLIC)
        self.assertEqual(manifest["archiveSha256"], artifact.sha256(output / "closure.tar"))

    def test_private_bootstrap_python_is_rejected_before_export_and_import(self):
        roots = {**self.manifest["roots"], "python": SYSTEM}
        lock = Path(SOURCE) / "flake.lock"
        original_is_file = Path.is_file
        output = self.directory / "private-python"
        with (
            patch.object(Path, "is_file", lambda path: path == lock or original_is_file(path)),
            patch.object(artifact, "closure_metadata", return_value=self.metadata),
            patch.object(artifact, "query_public_paths", return_value={PUBLIC}),
            patch.object(artifact, "export_entry") as exporter,
        ):
            with self.assertRaisesRegex(ValueError, "Bootstrap Python"):
                artifact.export_artifact("wsl", TESTED_SHA, roots, Path(SOURCE), output)
            exporter.assert_not_called()
        self.assertFalse(output.exists())
        self.manifest["roots"] = roots
        self.write_manifest()
        self.assert_rejected_without_nix()

    def test_required_export_failure_removes_incomplete_artifact(self):
        output = self.directory / "incomplete"
        lock = Path(SOURCE) / "flake.lock"
        original_is_file = Path.is_file
        with (
            patch.object(Path, "is_file", lambda path: path == lock or original_is_file(path)),
            patch.object(artifact, "closure_metadata", return_value=self.metadata),
            patch.object(artifact, "query_public_paths", return_value={PUBLIC}),
            patch.object(artifact, "export_entry", return_value=None),
        ):
            with self.assertRaisesRegex(ValueError, "required path"):
                artifact.export_artifact("wsl", TESTED_SHA, self.manifest["roots"], Path(SOURCE), output)
        self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
