"""Executable contract between hermes-home and the built bootstrap CLI."""

from __future__ import annotations

import hashlib
import json
import os
import subprocess
import unittest
from pathlib import Path


FIXTURE_ROOT = Path(__file__).resolve().parents[1] / "fixtures" / "hermes-home"
WRAPPER = FIXTURE_ROOT / "profile_sync.sh"
PROVENANCE = FIXTURE_ROOT / "profile_sync.provenance.json"
ENGINE = Path("/usr/local/bin/hermes-bootstrap")


class HermesHomeWrapperContractTests(unittest.TestCase):
    def test_exact_wrapper_routes_to_the_built_sync_profiles_cli(self) -> None:
        wrapper_bytes = WRAPPER.read_bytes()
        provenance = json.loads(PROVENANCE.read_text(encoding="ascii"))
        blob = (
            f"blob {len(wrapper_bytes)}\0".encode("ascii")
            + wrapper_bytes
        )

        self.assertEqual(
            provenance,
            {
                "source_repository": "rurusasu/hermes-home",
                "source_commit": (
                    "a2b82933e415444e04f845f3afb5a0369d52ed4f"
                ),
                "source_path": "scripts/profile_sync.sh",
                "git_blob_sha1": hashlib.sha1(
                    blob,
                    usedforsecurity=False,
                ).hexdigest(),
                "sha256": hashlib.sha256(wrapper_bytes).hexdigest(),
            },
        )
        self.assertTrue(WRAPPER.stat().st_mode & 0o111)
        self.assertTrue(ENGINE.is_file())
        self.assertTrue(ENGINE.stat().st_mode & 0o111)

        environment = {
            "HOME": "/nonexistent",
            "LANG": "C",
            "LC_ALL": "C",
            "PATH": "/usr/local/bin:/usr/bin:/bin",
        }
        direct = self._run((str(ENGINE), "sync-profiles"), environment)
        wrapped = self._run((str(WRAPPER),), environment)

        self.assertEqual(direct.returncode, 3)
        self.assertEqual(wrapped.returncode, direct.returncode)
        self.assertEqual(wrapped.stdout, direct.stdout)
        self.assertEqual(wrapped.stderr, direct.stderr)
        payload = json.loads(wrapped.stdout)
        self.assertEqual(payload["command"], "sync-profiles")
        self.assertEqual(
            [profile["name"] for profile in payload["profiles"]],
            ["rick", "hoffman", "risarisa", "nancy"],
        )
        self.assertTrue(
            all(
                profile["category"] == "credentials_unavailable"
                for profile in payload["profiles"]
            )
        )

    @staticmethod
    def _run(
        arguments: tuple[str, ...],
        environment: dict[str, str],
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            arguments,
            cwd="/tmp",
            env=environment,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
            timeout=10,
        )


if __name__ == "__main__":
    unittest.main()
