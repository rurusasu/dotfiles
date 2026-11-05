"""Mandatory artifact transfer and integrity at the Nix execution boundary."""

from __future__ import annotations

import base64
import hashlib
import json
import sys
import tempfile
import unittest
from contextlib import contextmanager
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
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name) / "artifact"
        self.roots = {"source": SOURCE, "system": SYSTEM}
        self.metadata = {
            SOURCE: {"path": SOURCE, "narHash": NAR_HASH, "narSize": 41, "references": [PUBLIC]},
            PUBLIC: {"path": PUBLIC, "narHash": NAR_HASH, "narSize": 42, "references": []},
            SYSTEM: {"path": SYSTEM, "narHash": NAR_HASH, "narSize": 43, "references": [SOURCE, PUBLIC]},
        }

    def export_payload(self, cache, path, metadata, maximum, timeout):
        # NAR bytes stand in for the external compression process. The actual
        # archive writer, manifest, extraction and digest checks all run.
        payload = path.encode()
        digest = hashlib.sha256(payload).digest()
        filename = digest.hex() + ".nar.zst"
        blob = cache / "nar" / filename
        blob.write_bytes(payload)
        info = cache / (Path(path).name.split("-", 1)[0] + ".narinfo")
        info.write_text(narinfo(metadata, filename, len(payload), base64.b64encode(digest).decode()))
        return info, blob, len(payload)

    @contextmanager
    def producer(self):
        original_is_file = Path.is_file
        original_sha256 = artifact.sha256
        lock = Path(SOURCE) / "flake.lock"
        with (
            patch.object(Path, "is_file", lambda path: path == lock or original_is_file(path)),
            patch.object(artifact, "sha256", lambda path: LOCK_DIGEST if path == lock else original_sha256(path)),
            patch.object(artifact, "closure_metadata", return_value=self.metadata),
            patch.object(artifact, "query_public_paths", return_value={PUBLIC}),
            patch.object(artifact, "export_entry", side_effect=self.export_payload),
        ):
            artifact.export_artifact("wsl", TESTED_SHA, self.roots, Path(SOURCE), self.directory)
            yield

    def test_exported_artifact_imports_exact_source_and_roots_without_building(self):
        with self.producer(), patch.object(artifact.subprocess, "run") as nix:
            imported = artifact.import_artifact("wsl", TESTED_SHA, self.directory)
        self.assertEqual(imported, self.roots)
        manifest = json.loads((self.directory / "manifest.json").read_text())
        self.assertEqual(manifest["testedSha"], TESTED_SHA)
        self.assertEqual(manifest["source"], {"path": SOURCE, "narHash": NAR_HASH, "flakeLockSha256": LOCK_DIGEST})
        self.assertEqual(json.loads((self.directory / "roots.json").read_text()), self.roots)
        self.assertTrue(nix.called)
        for call in nix.call_args_list:
            command = call.args[0]
            options = {command[index + 1]: command[index + 2] for index, value in enumerate(command) if value == "--option"}
            self.assertEqual(options.get("max-jobs"), "0")
            self.assertEqual(options.get("builders"), "")

    def test_corrupt_artifact_is_rejected_before_importing_any_store_path(self):
        with self.producer():
            with (self.directory / "closure.tar").open("ab") as archive:
                archive.write(b"corrupt transfer")
            with patch.object(artifact.subprocess, "run") as nix:
                with self.assertRaisesRegex(ValueError, "archive digest mismatch"):
                    artifact.import_artifact("wsl", TESTED_SHA, self.directory)
                nix.assert_not_called()
        self.assertFalse((self.directory / "roots.json").exists())


if __name__ == "__main__":
    unittest.main()
