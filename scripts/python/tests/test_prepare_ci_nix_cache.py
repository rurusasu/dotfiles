"""Protect the two costly failures at the optional cache export boundary."""

from __future__ import annotations

import base64
import hashlib
import importlib.util
import os
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


class CacheTests(unittest.TestCase):
    def test_bounded_export_keeps_fitting_private_closure(self):
        public, dependency, large, small = (
            f"/nix/store/{letter * 32}-{name}"
            for letter, name in zip("abcd", ("public", "dependency", "large", "small"))
        )
        records = {
            path: {
                "path": path,
                "references": references,
                "narHash": "sha256-" + base64.b64encode(b"h" * 32).decode(),
                "narSize": size,
            }
            for path, references, size in (
                (public, [], 10**18),
                (dependency, [public], 100),
                (large, [dependency], 100_000),
                (small, [dependency], 100),
            )
        }

        def compress(path, destination, maximum_bytes, timeout=120):
            payload = path.encode() * (2000 if path == large else 1)
            if len(payload) > maximum_bytes:
                return None
            destination.write_bytes(payload)
            digest = hashlib.sha256(payload)
            return len(payload), digest.hexdigest(), base64.b64encode(digest.digest()).decode()

        with tempfile.TemporaryDirectory() as temporary:
            destination = Path(temporary) / "cache"
            output = Path(temporary) / "github-output"
            with (
                patch.dict(os.environ, {"GITHUB_OUTPUT": str(output)}),
                patch.object(cache, "store_paths", return_value=list(records)),
                patch.object(cache, "path_metadata", return_value=records),
                patch.object(cache, "query_public_paths", return_value={public}),
                patch.object(cache, "compress_path", side_effect=compress),
                patch.object(cache.shutil, "disk_usage", return_value=SimpleNamespace(free=100 * 1024**2)),
            ):
                cache.export_cache(destination, cache.ARCHIVE_RESERVE + 3000)
            entries = cache.cache_entries(destination)
            selected = {path for path, *_ in entries}
            self.assertEqual(selected, {dependency, small})
            self.assertTrue(all(refs <= selected | {public} for _, _, _, refs in entries))
            self.assertLessEqual(sum(p.stat().st_size for p in destination.rglob("*") if p.is_file()), 3000)
            self.assertIn("cacheable=true", output.read_text())

    def test_stream_stops_before_compressed_byte_budget(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            for name, source in {
                "nix-store": "import sys\nsys.stdout.buffer.write(b'x' * 1000000)\n",
                "zstd": "import sys\nsys.stdout.buffer.write(sys.stdin.buffer.read())\n",
            }.items():
                executable = directory / name
                executable.write_text(f"#!{sys.executable}\n" + source)
                executable.chmod(0o755)
            destination = directory / "payload"
            with patch.dict(os.environ, {"PATH": str(directory)}):
                self.assertIsNone(cache.compress_path("/fixture", destination, 1000))
            self.assertLessEqual(destination.stat().st_size, 1000)


if __name__ == "__main__":
    unittest.main()
