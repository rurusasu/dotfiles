"""Executable contract between hermes-home and the built bootstrap CLI."""

from __future__ import annotations

import hashlib
import json
import os
import subprocess
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from build_fixture import private_fixture
from hermes_bootstrap.engine_lock import EngineLock


FIXTURE_ROOT = Path(__file__).resolve().parents[1] / "fixtures" / "hermes-home"
PINNED_WRAPPER = FIXTURE_ROOT / "profile_sync.sh"
WRAPPER = Path(
    os.environ.get(
        "DOTFILES_HERMES_MANAGED_WRAPPER",
        str(Path(__file__).resolve().parents[4] / "scripts" / "sh" / "hermes-profile-sync.sh"),
    )
)
PROVENANCE = FIXTURE_ROOT / "profile_sync.provenance.json"
ENGINE = Path(os.environ.get("DOTFILES_HERMES_BOOTSTRAP_EXECUTABLE", "hermes-bootstrap"))
MODE_CONTRACT_ERROR = "wrapper provenance mode contract failed"


class HermesHomeWrapperContractTests(unittest.TestCase):
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

    def test_pinned_upstream_wrapper_matches_its_provenance(self) -> None:
        wrapper_bytes = PINNED_WRAPPER.read_bytes()
        provenance = json.loads(PROVENANCE.read_text(encoding="ascii"))
        blob = (
            f"blob {len(wrapper_bytes)}\0".encode("ascii")
            + wrapper_bytes
        )

        self.assertEqual(
            provenance,
            {
                "source_repository": "rurusasu/hermes-profile-alfred",
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
        self.assertTrue(PINNED_WRAPPER.stat().st_mode & 0o111)

    def test_nix_managed_wrapper_routes_to_the_built_sync_profiles_cli(self) -> None:
        self.assertTrue(ENGINE.is_file())
        self.assertTrue(ENGINE.stat().st_mode & 0o111)
        self.assertTrue(WRAPPER.is_file())
        self.assertTrue(WRAPPER.stat().st_mode & 0o111)

        environment = {
            "HOME": "/nonexistent",
            "LANG": "C",
            "LC_ALL": "C",
            "PATH": "/usr/local/bin:/usr/bin:/bin",
            "DOTFILES_HERMES_BOOTSTRAP_EXECUTABLE": str(ENGINE),
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
            ["rick", "hoffman", "risarisa", "nancy", "kuroda", "shiraishi"],
        )
        self.assertTrue(
            all(
                profile["category"] == "credentials_unavailable"
                for profile in payload["profiles"]
            )
        )

    def test_independent_build_fixtures_do_not_share_engine_locks(self) -> None:
        base_cli = Path(os.environ["DOTFILES_HERMES_TEST_BASE_CLI"])
        template = Path(os.environ["DOTFILES_HERMES_TEST_MANIFEST_TEMPLATE"])
        shell = os.environ["DOTFILES_HERMES_TEST_SHELL"]
        with tempfile.TemporaryDirectory(prefix="hermes build # quoted : ") as temporary_directory:
            temporary_root = Path(temporary_directory).resolve()
            with (
                private_fixture(template, base_cli, temporary_root, shell) as first,
                private_fixture(template, base_cli, temporary_root, shell) as second,
            ):
                self.assertNotEqual(first.home, second.home)
                environments = [
                    {
                        "HOME": "/nonexistent",
                        "LANG": "C",
                        "LC_ALL": "C",
                        "PATH": "/usr/local/bin:/usr/bin:/bin",
                        "DOTFILES_HERMES_BOOTSTRAP_EXECUTABLE": str(fixture.executable),
                    }
                    for fixture in (first, second)
                ]
                lock = EngineLock.acquire(first.home)
                try:
                    # Both processes are joined before either private tree is
                    # cleaned. A real held lock in A must not contaminate B.
                    with ThreadPoolExecutor(max_workers=2) as pool:
                        blocked = pool.submit(
                            self._run,
                            (str(first.executable), "sync-profiles"),
                            environments[0],
                        )
                        independent = pool.submit(self._run, (str(WRAPPER),), environments[1])
                        first_result = blocked.result()
                        wrapped = independent.result()
                    self.assertEqual(first_result.returncode, 4)
                    self.assertTrue(all(
                        profile["category"] == "repository"
                        for profile in json.loads(first_result.stdout)["profiles"]
                    ))
                    direct = self._run((str(second.executable), "sync-profiles"), environments[1])
                    self.assertEqual(direct.returncode, 3)
                    self.assertEqual(wrapped.returncode, 3)
                    self.assertEqual(wrapped.stdout, direct.stdout)
                    self.assertEqual(wrapped.stderr, direct.stderr)
                    profiles = json.loads(wrapped.stdout)["profiles"]
                    self.assertEqual(
                        [profile["name"] for profile in profiles],
                        ["rick", "hoffman", "risarisa", "nancy", "kuroda", "shiraishi"],
                    )
                    self.assertTrue(all(
                        profile["category"] == "credentials_unavailable" for profile in profiles
                    ))
                    lock.require_held()
                finally:
                    lock.close()
                released = self._run((str(first.executable), "sync-profiles"), environments[0])
                self.assertEqual(released.returncode, 3)
                self.assertEqual(released.stdout, direct.stdout)
                self.assertEqual(released.stderr, direct.stderr)
            self.assertFalse(first.root.exists())
            self.assertFalse(second.root.exists())

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

if __name__ == "__main__":
    unittest.main()
