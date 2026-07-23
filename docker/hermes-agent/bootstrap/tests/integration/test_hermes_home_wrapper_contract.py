"""Executable contract between hermes-home and the built bootstrap CLI."""

from __future__ import annotations

import hashlib
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


FIXTURE_ROOT = Path(__file__).resolve().parents[1] / "fixtures" / "hermes-home"
WRAPPER = FIXTURE_ROOT / "profile_sync.sh"
PROVENANCE = FIXTURE_ROOT / "profile_sync.provenance.json"
ENGINE = Path("/usr/local/bin/hermes-bootstrap")
DOTFILES_ROOT = Path(__file__).resolve().parents[5]
FIXTURE_PATH = WRAPPER.relative_to(DOTFILES_ROOT)
HERMES_HOME_ROOT = Path(
    os.environ.get(
        "HERMES_HOME_PROVENANCE_REPOSITORY",
        DOTFILES_ROOT.parent / "hermes-home-profile-sync",
    )
)
MODE_CONTRACT_ERROR = "wrapper provenance mode contract failed"


class HermesHomeWrapperContractTests(unittest.TestCase):
    def test_committed_fixture_tree_mode_is_executable(self) -> None:
        if not self._is_git_worktree(DOTFILES_ROOT):
            self.skipTest("committed fixture mode requires a Git worktree")
        self._assert_committed_tree_mode(
            DOTFILES_ROOT,
            "HEAD",
            FIXTURE_PATH,
            "dotfiles fixture",
        )

    def test_committed_hermes_home_source_tree_mode_is_executable(self) -> None:
        if not self._is_git_worktree(HERMES_HOME_ROOT):
            self.skipTest("committed source mode requires the hermes-home worktree")
        provenance = json.loads(PROVENANCE.read_text(encoding="ascii"))
        self._assert_committed_tree_mode(
            HERMES_HOME_ROOT,
            provenance["source_commit"],
            Path(provenance["source_path"]),
            "hermes-home source",
        )

    def test_committed_tree_mode_rejects_non_executable_source_or_fixture(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            repository = Path(temporary_directory) / "fixture-repository"
            script = repository / "profile_sync.sh"
            self._run_git("init", "--initial-branch=main", str(repository))
            script.write_text("#!/usr/bin/env bash\n", encoding="ascii")
            script.chmod(0o644)
            self._run_git("-C", str(repository), "add", script.name)
            self._run_git(
                "-C",
                str(repository),
                "-c",
                "user.email=contract@example.invalid",
                "-c",
                "user.name=Contract Test",
                "commit",
                "-m",
                "add non-executable fixture",
            )
            script.chmod(0o755)
            self.assertTrue(script.stat().st_mode & 0o111)

            for label in ("hermes-home source", "dotfiles fixture"):
                with self.subTest(label=label), self.assertRaisesRegex(
                    AssertionError,
                    MODE_CONTRACT_ERROR,
                ):
                    self._assert_committed_tree_mode(
                        repository,
                        "HEAD",
                        script.relative_to(repository),
                        label,
                    )

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

    def _assert_committed_tree_mode(
        self,
        repository: Path,
        commit: str,
        path: Path,
        label: str,
    ) -> None:
        entry = self._run_git(
            "-C",
            str(repository),
            "ls-tree",
            commit,
            "--",
            str(path),
        ).stdout.strip()
        mode = entry.split(maxsplit=1)[0] if entry else "missing"
        self.assertEqual(
            mode,
            "100755",
            MODE_CONTRACT_ERROR,
        )

    @staticmethod
    def _run_git(*arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ("git", *arguments),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=True,
            timeout=10,
        )

    @staticmethod
    def _is_git_worktree(repository: Path) -> bool:
        result = subprocess.run(
            ("git", "-C", str(repository), "rev-parse", "--is-inside-work-tree"),
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            check=False,
            timeout=10,
        )
        return result.returncode == 0 and result.stdout.strip() == "true"


if __name__ == "__main__":
    unittest.main()
