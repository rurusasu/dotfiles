"""Runtime contracts for the bounded optional Nix cache exporter."""

from __future__ import annotations

import base64
import hashlib
import importlib.util
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "prepare_ci_nix_cache", Path(__file__).parents[1] / "prepare_ci_nix_cache.py"
)
cache = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cache)


def store_path(letter, name):
    return f"/nix/store/{letter * 32}-{name}"


def record(path, references=(), size=100):
    return {
        "path": path,
        "references": list(references),
        "narHash": "sha256-" + base64.b64encode(b"h" * 32).decode(),
        "narSize": size,
    }


class ExportTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.output = self.root / "github-output"
        self.environment = patch.dict(os.environ, {"GITHUB_OUTPUT": str(self.output)})
        self.environment.start()
        self.addCleanup(self.environment.stop)

    def export(self, records, sizes, public=(), budget=3000, free=1024**3):
        def compress(path, destination, maximum_bytes, timeout=120):
            payload = bytes([len(path) % 255]) * sizes[path]
            if len(payload) > maximum_bytes:
                # A bounded failed candidate must leave no advertised entry.
                destination.write_bytes(payload[:maximum_bytes])
                return None
            destination.write_bytes(payload)
            digest = hashlib.sha256(payload)
            return len(payload), digest.hexdigest(), base64.b64encode(digest.digest()).decode()

        destination = self.root / "cache"
        with (
            patch.object(cache, "store_paths", return_value=sorted(records)),
            patch.object(cache, "path_metadata", return_value=records),
            patch.object(cache, "query_public_paths", return_value=set(public)),
            patch.object(cache, "compress_path", side_effect=compress),
            patch.object(cache.shutil, "disk_usage", return_value=SimpleNamespace(free=free)),
        ):
            cache.export_cache(destination, cache.ARCHIVE_RESERVE + budget)
        return destination

    def test_large_root_does_not_discard_fitting_dependencies(self):
        dependency = store_path("a", "shared-dependency")
        large = store_path("b", "large-application")
        other = store_path("c", "other-application")
        records = {
            dependency: record(dependency),
            large: record(large, [dependency], 100_000),
            other: record(other, [dependency]),
        }
        destination = self.export(records, {dependency: 100, large: 100_000, other: 90})
        entries = cache.cache_entries(destination)
        self.assertEqual({path for path, *_ in entries}, {dependency, other})
        self.assertTrue(all(refs <= {dependency, other} for _, _, _, refs in entries))
        self.assertIn("cacheable=true", self.output.read_text())
        self.assertFalse((destination / "nar" / ".candidate").exists())
        self.assertLessEqual(sum(p.stat().st_size for p in destination.rglob("*") if p.is_file()), 3000)

    def test_public_huge_reference_is_not_exported_or_counted_as_scratch(self):
        public = store_path("a", "huge-public")
        private = store_path("b", "small-private")
        destination = self.export(
            {public: record(public, size=10**18), private: record(private, [public])},
            {private: 100}, public={public}, free=100 * 1024**2,
        )
        self.assertEqual({path for path, *_ in cache.cache_entries(destination)}, {private})
        self.assertIn("cacheable=true", self.output.read_text())

    def test_no_root_is_advertised_when_private_reference_is_skipped(self):
        huge = store_path("a", "huge-dependency")
        root = store_path("b", "small-root")
        destination = self.export(
            {huge: record(huge), root: record(root, [huge])},
            {huge: 100_000, root: 20},
        )
        self.assertEqual(cache.cache_entries(destination), [])
        self.assertIn("cacheable=false", self.output.read_text())

    def test_public_reference_must_also_have_public_transitive_dependencies(self):
        private = store_path("a", "private-reference")
        claimed_public = store_path("b", "remote-root")
        root = store_path("c", "root")
        records = {
            private: record(private), claimed_public: record(claimed_public, [private]),
            root: record(root, [claimed_public]),
        }
        destination = self.export(records, {path: 30 for path in records}, public={claimed_public})
        self.assertEqual({path for path, *_ in cache.cache_entries(destination)}, set(records))

    def test_self_references_fit_but_unresolved_cycles_are_skipped(self):
        a, b, c = [store_path(letter, letter) for letter in "abc"]
        records = {a: record(a, [a]), b: record(b, [c]), c: record(c, [b])}
        destination = self.export(records, {path: 30 for path in records})
        self.assertEqual({path for path, *_ in cache.cache_entries(destination)}, {a})

    def test_insufficient_scratch_preserves_previous_generation(self):
        previous = self.root / "previous"
        previous.mkdir()
        (previous / "keep").write_text("previous")
        path = store_path("a", "output")
        destination = self.export({path: record(path)}, {path: 30}, free=1024)
        self.assertEqual(cache.cache_entries(destination), [])
        self.assertEqual((previous / "keep").read_text(), "previous")
        self.assertIn("cacheable=false", self.output.read_text())

    def test_metadata_errors_do_not_claim_success(self):
        destination = self.root / "cache"
        with (
            patch.object(cache, "store_paths", return_value=[store_path("a", "output")]),
            patch.object(cache, "path_metadata", side_effect=ValueError("invalid metadata")),
        ):
            with self.assertRaisesRegex(ValueError, "invalid metadata"):
                cache.export_cache(destination, cache.ARCHIVE_RESERVE + 3000)
        self.assertFalse(self.output.exists())


class MetadataTests(unittest.TestCase):
    def test_nix_object_and_lix_array_are_normalized(self):
        path = store_path("a", "output")
        entry = record(path)
        import json
        for metadata in ({path: {key: value for key, value in entry.items() if key != "path"}}, [entry]):
            with patch.object(cache.subprocess, "run", return_value=SimpleNamespace(stdout=json.dumps(metadata))):
                self.assertEqual(cache.path_metadata([path]), {path: entry})

    def test_all_configured_remote_caches_are_considered(self):
        a, b = store_path("a", "mirror-public"), store_path("b", "private")
        seen = []
        def run(arguments, **kwargs):
            seen.append(arguments)
            if arguments[:2] == ["nix", "config"]:
                return SimpleNamespace(stdout="https://official https://mirror file:///restored")
            return SimpleNamespace(stdout="\n".join([a, b] if arguments[2] == "https://official" else [b]))
        with patch.object(cache.subprocess, "run", side_effect=run):
            self.assertEqual(cache.query_public_paths([a, b]), {a})
        self.assertFalse(any("file:///restored" in arguments for arguments in seen))

    def test_one_remote_outage_does_not_hide_other_public_caches(self):
        path = store_path("a", "public")
        def run(arguments, **kwargs):
            if arguments[:2] == ["nix", "config"]:
                return SimpleNamespace(stdout="https://offline https://healthy")
            if arguments[2] == "https://offline":
                raise subprocess.TimeoutExpired(arguments, 60)
            return SimpleNamespace(stdout="")
        with patch.object(cache.subprocess, "run", side_effect=run):
            self.assertEqual(cache.query_public_paths([path]), {path})


class PipelineTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        for name, source in {
            "nix-store": "import sys\nsys.stdout.buffer.write(b'x' * 1000000)\n",
            "zstd": "import sys\nsys.stdout.buffer.write(sys.stdin.buffer.read())\n",
        }.items():
            executable = self.root / name
            executable.write_text(f"#!{sys.executable}\n" + source)
            executable.chmod(0o755)
        self.environment = patch.dict(os.environ, {"PATH": str(self.root)})
        self.environment.start()
        self.addCleanup(self.environment.stop)

    def test_compressed_stream_stops_before_byte_limit(self):
        destination = self.root / "payload"
        self.assertIsNone(cache.compress_path("/fixture", destination, 1000))
        self.assertLessEqual(destination.stat().st_size, 1000)

    def test_compressor_failure_propagates_its_diagnostics(self):
        (self.root / "zstd").write_text(f"#!{sys.executable}\nimport sys\nsys.stderr.write('compressor failed')\nsys.exit(7)\n")
        with self.assertRaisesRegex(RuntimeError, "compressor failed"):
            cache.compress_path("/fixture", self.root / "payload", 1000)


if __name__ == "__main__":
    unittest.main()
