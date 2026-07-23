from __future__ import annotations

import hashlib
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


VERIFIER = Path(__file__).with_name("verify_profile_sync_provenance.py")
FIXTURE_PATH = Path(
    "docker/hermes-agent/bootstrap/tests/fixtures/hermes-home/profile_sync.sh"
)
PROVENANCE_PATH = FIXTURE_PATH.with_name("profile_sync.provenance.json")
SOURCE_PATH = Path("scripts/profile_sync.sh")
SOURCE_REPOSITORY = "rurusasu/hermes-home"


class ProfileSyncProvenanceVerifierTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.dotfiles = self.root / "dotfiles"
        self.source = self.root / "hermes-home"
        self.wrapper_bytes = (
            b"#!/usr/bin/env bash\n"
            b"set -euo pipefail\n"
            b"# secret-marker\n"
            b'exec hermes-bootstrap sync-profiles "$@"\n'
        )

        self._init_repository(self.source)
        self._write_executable(self.source / SOURCE_PATH, self.wrapper_bytes)
        self._commit_all(self.source, "add source wrapper")
        self.source_commit = self._git(self.source, "rev-parse", "HEAD").stdout.strip()

        blob = f"blob {len(self.wrapper_bytes)}\0".encode("ascii") + self.wrapper_bytes
        self.provenance = {
            "source_repository": SOURCE_REPOSITORY,
            "source_commit": self.source_commit,
            "source_path": SOURCE_PATH.as_posix(),
            "git_blob_sha1": hashlib.sha1(blob, usedforsecurity=False).hexdigest(),
            "sha256": hashlib.sha256(self.wrapper_bytes).hexdigest(),
        }

        self._init_repository(self.dotfiles)
        self._write_executable(
            self.dotfiles / FIXTURE_PATH,
            self.wrapper_bytes,
        )
        provenance = self.dotfiles / PROVENANCE_PATH
        provenance.write_text(
            json.dumps(self.provenance, indent=2) + "\n",
            encoding="ascii",
        )
        self._commit_all(self.dotfiles, "add fixture provenance")

    def test_accepts_matching_clean_git_repositories(self) -> None:
        result = self._verify()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout,
            "profile sync provenance verified\n",
        )
        self.assertEqual(result.stderr, "")

    def test_emits_only_the_validated_source_commit(self) -> None:
        result = self._run_verifier(
            "source-commit",
            "--dotfiles-repository",
            str(self.dotfiles),
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, f"{self.source_commit}\n")
        self.assertEqual(result.stderr, "")

    def test_rejects_non_git_repository_roots(self) -> None:
        non_git = self.root / "not-a-repository"
        non_git.mkdir()

        with self.subTest(repository="dotfiles"):
            self._assert_failure(
                "dotfiles repository is not a Git worktree root",
                dotfiles=non_git,
            )
        with self.subTest(repository="source"):
            self._assert_failure(
                "source repository is not a Git worktree root",
                source=non_git,
            )
        with self.subTest(repository="source-subdirectory"):
            self._assert_failure(
                "source repository is not a Git worktree root",
                source=self.source / "scripts",
            )

    def test_rejects_malformed_provenance_schema_without_leaking_values(
        self,
    ) -> None:
        malformed_documents: dict[str, tuple[str, str]] = {
            "invalid-json": (
                '{"source_repository": "secret-marker"',
                "provenance is not valid JSON",
            ),
            "not-object": (
                '["secret-marker"]',
                "provenance must be a JSON object",
            ),
            "duplicate-key": (
                """\
{
  "source_repository": "rurusasu/hermes-home",
  "source_repository": "secret-marker",
  "source_commit": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "source_path": "scripts/profile_sync.sh",
  "git_blob_sha1": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
  "sha256": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
}
""",
                "provenance contains duplicate keys",
            ),
            "missing-key": (
                json.dumps(
                    {
                        key: value
                        for key, value in self.provenance.items()
                        if key != "sha256"
                    }
                ),
                "provenance keys do not match the schema",
            ),
            "extra-key": (
                json.dumps(
                    {
                        **self.provenance,
                        "secret-marker": "must-not-leak",
                    }
                ),
                "provenance keys do not match the schema",
            ),
        }
        for case, (document, reason) in malformed_documents.items():
            with self.subTest(case=case):
                self._write_provenance(document)
                self._commit_all(self.dotfiles, f"set {case} provenance")
                self._assert_failure(reason)
                self._git(self.dotfiles, "reset", "--hard", "HEAD^")

    def test_rejects_malformed_provenance_values(self) -> None:
        invalid_values: dict[str, tuple[str, object, str]] = {
            "repository-type": (
                "source_repository",
                42,
                "provenance source_repository is invalid",
            ),
            "repository-value": (
                "source_repository",
                "secret-marker/hermes-home",
                "provenance source_repository is invalid",
            ),
            "commit": (
                "source_commit",
                "A" * 40,
                "provenance source_commit is invalid",
            ),
            "source-path-type": (
                "source_path",
                42,
                "provenance source_path is invalid",
            ),
            "source-path-absolute": (
                "source_path",
                "/secret-marker/profile_sync.sh",
                "provenance source_path is invalid",
            ),
            "source-path-traversal": (
                "source_path",
                "../secret-marker/profile_sync.sh",
                "provenance source_path is invalid",
            ),
            "source-path-backslash": (
                "source_path",
                r"scripts\secret-marker.sh",
                "provenance source_path is invalid",
            ),
            "source-path-dot": (
                "source_path",
                ".",
                "provenance source_path is invalid",
            ),
            "blob": (
                "git_blob_sha1",
                "g" * 40,
                "provenance git_blob_sha1 is invalid",
            ),
            "sha256": (
                "sha256",
                "a" * 63,
                "provenance sha256 is invalid",
            ),
        }
        for case, (key, value, reason) in invalid_values.items():
            with self.subTest(case=case):
                self._replace_provenance(**{key: value})
                self._commit_all(self.dotfiles, f"set {case} provenance")
                self._assert_failure(reason)
                self._git(self.dotfiles, "reset", "--hard", "HEAD^")

    def test_rejects_dirty_tracked_inputs(self) -> None:
        cases = (
            (
                "source",
                self.source / SOURCE_PATH,
                b"secret-marker: dirty source\n",
                "source path is dirty",
            ),
            (
                "fixture",
                self.dotfiles / FIXTURE_PATH,
                b"secret-marker: dirty fixture\n",
                "dotfiles fixture is dirty",
            ),
            (
                "provenance",
                self.dotfiles / PROVENANCE_PATH,
                b'{"secret-marker": "dirty provenance"}\n',
                "dotfiles provenance is dirty",
            ),
        )
        for case, path, contents, reason in cases:
            with self.subTest(case=case):
                original = path.read_bytes()
                path.write_bytes(contents)
                self._assert_failure(reason)
                path.write_bytes(original)

    def test_rejects_staged_changes_hidden_by_a_restored_worktree(self) -> None:
        cases = (
            (
                self.source,
                SOURCE_PATH,
                b"secret-marker: staged source\n",
                "source path is dirty",
            ),
            (
                self.dotfiles,
                FIXTURE_PATH,
                b"secret-marker: staged fixture\n",
                "dotfiles fixture is dirty",
            ),
            (
                self.dotfiles,
                PROVENANCE_PATH,
                b'{"secret-marker": "staged provenance"}\n',
                "dotfiles provenance is dirty",
            ),
        )
        for repository, relative_path, staged, reason in cases:
            with self.subTest(path=relative_path):
                path = repository / relative_path
                original = path.read_bytes()
                path.write_bytes(staged)
                self._git(
                    repository,
                    "add",
                    "--",
                    relative_path.as_posix(),
                )
                path.write_bytes(original)
                self._assert_failure(reason)
                self._git(
                    repository,
                    "reset",
                    "HEAD",
                    "--",
                    relative_path.as_posix(),
                )

    def test_rejects_wrong_source_head(self) -> None:
        self._git(
            self.source,
            "commit",
            "--allow-empty",
            "-m",
            "advance source head",
        )

        self._assert_failure("source HEAD does not match provenance source_commit")

    def test_rejects_untracked_fixture_or_provenance(self) -> None:
        cases = (
            (FIXTURE_PATH, "dotfiles fixture is not tracked at HEAD"),
            (PROVENANCE_PATH, "dotfiles provenance is not tracked at HEAD"),
        )
        for path, reason in cases:
            with self.subTest(path=path):
                self._git(
                    self.dotfiles,
                    "rm",
                    "--cached",
                    "--",
                    path.as_posix(),
                )
                self._git(
                    self.dotfiles,
                    "commit",
                    "-m",
                    f"untrack {path.name}",
                )
                self._assert_failure(reason)
                self._git(self.dotfiles, "reset", "--hard", "HEAD^")

    def test_rejects_untracked_source_path(self) -> None:
        self._git(
            self.source,
            "rm",
            "--",
            SOURCE_PATH.as_posix(),
        )
        self._git(self.source, "commit", "-m", "remove source wrapper")
        self._write_executable(
            self.source / SOURCE_PATH,
            self.wrapper_bytes,
        )
        source_commit = self._git(
            self.source,
            "rev-parse",
            "HEAD",
        ).stdout.strip()
        self._replace_provenance(source_commit=source_commit)
        self._commit_all(self.dotfiles, "update source commit")

        source_status = self._git(
            self.source,
            "status",
            "--short",
            "--",
            SOURCE_PATH.as_posix(),
        )
        self.assertEqual(
            source_status.stdout,
            f"?? {SOURCE_PATH.as_posix()}\n",
        )

        self._assert_failure("source path is not tracked at HEAD")

    def test_rejects_non_executable_committed_modes(self) -> None:
        with self.subTest(repository="source"):
            self._git(
                self.source,
                "update-index",
                "--chmod=-x",
                "--",
                SOURCE_PATH.as_posix(),
            )
            self._git(self.source, "commit", "-m", "drop source executable mode")
            (self.source / SOURCE_PATH).chmod(0o644)
            source_commit = self._git(self.source, "rev-parse", "HEAD").stdout.strip()
            self._replace_provenance(source_commit=source_commit)
            self._commit_all(self.dotfiles, "update source commit")
            self._assert_failure("source path committed mode is not 100755")
            self._git(self.dotfiles, "reset", "--hard", "HEAD^")
            self._git(self.source, "reset", "--hard", "HEAD^")

        with self.subTest(repository="dotfiles"):
            self._git(
                self.dotfiles,
                "update-index",
                "--chmod=-x",
                "--",
                FIXTURE_PATH.as_posix(),
            )
            self._git(
                self.dotfiles,
                "commit",
                "-m",
                "drop fixture executable mode",
            )
            (self.dotfiles / FIXTURE_PATH).chmod(0o644)
            self._assert_failure("dotfiles fixture committed mode is not 100755")

    def test_rejects_git_blob_or_sha256_mismatches(self) -> None:
        mismatches = (
            (
                "git-blob",
                {"git_blob_sha1": "0" * 40},
                "source Git blob does not match provenance",
            ),
            (
                "sha256",
                {"sha256": "0" * 64},
                "source SHA-256 does not match provenance",
            ),
        )
        for case, replacements, reason in mismatches:
            with self.subTest(case=case):
                self._replace_provenance(**replacements)
                self._commit_all(self.dotfiles, f"set wrong {case}")
                self._assert_failure(reason)
                self._git(self.dotfiles, "reset", "--hard", "HEAD^")

    def test_rejects_fixture_that_does_not_match_the_source_blob(self) -> None:
        replacement = self.wrapper_bytes + b"# source-only change\n"
        self._write_executable(self.source / SOURCE_PATH, replacement)
        self._commit_all(self.source, "change source wrapper")
        source_commit = self._git(self.source, "rev-parse", "HEAD").stdout.strip()
        blob = f"blob {len(replacement)}\0".encode("ascii") + replacement
        self._replace_provenance(
            source_commit=source_commit,
            git_blob_sha1=hashlib.sha1(blob, usedforsecurity=False).hexdigest(),
            sha256=hashlib.sha256(replacement).hexdigest(),
        )
        self._commit_all(self.dotfiles, "update source provenance")

        self._assert_failure("dotfiles fixture Git blob does not match provenance")

    def _verify(
        self,
        *,
        dotfiles: Path | None = None,
        source: Path | None = None,
    ) -> subprocess.CompletedProcess[str]:
        return self._run_verifier(
            "verify",
            "--dotfiles-repository",
            str(dotfiles or self.dotfiles),
            "--source-repository",
            str(source or self.source),
        )

    def _assert_failure(
        self,
        reason: str,
        *,
        dotfiles: Path | None = None,
        source: Path | None = None,
    ) -> None:
        result = self._verify(dotfiles=dotfiles, source=source)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertEqual(
            result.stderr,
            f"profile sync provenance verification failed: {reason}\n",
        )
        self.assertNotIn("secret-marker", result.stderr)
        self.assertNotIn(self.wrapper_bytes.decode("ascii"), result.stderr)

    @staticmethod
    def _run_verifier(
        *arguments: str,
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            (
                sys.executable,
                str(VERIFIER),
                *arguments,
            ),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
            timeout=10,
        )

    def _replace_provenance(self, **replacements: object) -> None:
        self._write_provenance(
            json.dumps(
                {**self.provenance, **replacements},
                indent=2,
            )
            + "\n"
        )

    def _write_provenance(self, document: str) -> None:
        (self.dotfiles / PROVENANCE_PATH).write_text(
            document,
            encoding="ascii",
        )

    def _init_repository(self, repository: Path) -> None:
        repository.mkdir(parents=True)
        self._git(repository, "init", "--initial-branch=main")
        self._git(repository, "config", "user.email", "test@example.invalid")
        self._git(repository, "config", "user.name", "Provenance Test")
        self._git(repository, "config", "core.fileMode", "true")

    def _commit_all(self, repository: Path, message: str) -> None:
        self._git(repository, "add", ".")
        for relative_path in (SOURCE_PATH, FIXTURE_PATH):
            if (repository / relative_path).is_file():
                self._git(
                    repository,
                    "update-index",
                    "--chmod=+x",
                    "--",
                    relative_path.as_posix(),
                )
        self._git(repository, "commit", "-m", message)

    @staticmethod
    def _write_executable(path: Path, content: bytes) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
        path.chmod(0o755)

    @staticmethod
    def _git(
        repository: Path,
        *arguments: str,
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ("git", "-C", str(repository), *arguments),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=True,
            timeout=10,
        )


if __name__ == "__main__":
    unittest.main()
