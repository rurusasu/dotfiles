"""Contracts for the local composite action that routes CI changes."""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
ACTION_PATH = REPOSITORY_ROOT / ".github" / "actions" / "detect-ci-changes" / "action.yml"
DETECTOR_PATH = REPOSITORY_ROOT / "scripts" / "python" / "detect_ci_changes.py"
MANIFEST_PATH = REPOSITORY_ROOT / "ci" / "path-routing.json"
SETUP_PYTHON = "actions/setup-python@ece7cb06caefa5fff74198d8649806c4678c61a1"
INPUTS = {"base-sha", "head-sha", "run-all", "manifest"}
OUTPUTS = {
    "linux",
    "darwin",
    "wsl",
    "windows",
    "contract",
    "nix",
    "chezmoi",
    "hermes",
    "devcontainer",
    "package_catalog",
}


class DetectCiActionContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.action = ACTION_PATH.read_text(encoding="utf-8") if ACTION_PATH.is_file() else ""

    def test_action_declares_the_stable_interface(self) -> None:
        self.assertTrue(ACTION_PATH.is_file(), "composite action is missing")
        self.assertEqual(self._top_level_keys("inputs"), INPUTS)
        self.assertEqual(self._top_level_keys("outputs"), OUTPUTS)

        for output in OUTPUTS:
            self.assertIn(
                f"    value: ${{{{ steps.detect.outputs.{output} }}}}",
                self._section("outputs"),
            )

    def test_action_uses_only_pinned_python_setup_at_version_314(self) -> None:
        uses = [line.strip().removeprefix("- ") for line in self.action.splitlines() if "uses:" in line]

        self.assertEqual(uses, [f"uses: {SETUP_PYTHON}"])
        self.assertIn('python-version: "3.14"', self.action)

    def test_action_shell_routes_changed_paths_to_the_detector(self) -> None:
        script = self._run_script()

        self.assertIn("set -euo pipefail", script)
        self.assertIn('paths_file="${RUNNER_TEMP}/ci-changed-paths.txt"', script)
        self.assertIn("git diff --name-only --no-renames", script)
        self.assertNotIn("--diff-filter=ACMR", script)
        self.assertIn("--paths-file", script)
        self.assertIn("--github-output", script)
        self.assertIn("--all", script)
        self.assertIn("scripts/python/detect_ci_changes.py", script)

    def test_non_all_mode_passes_only_changed_paths_to_the_detector(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            repository = self._make_test_repository(Path(temporary_directory))
            base_sha = self._git(repository, "rev-parse", "HEAD")
            (repository / "scripts" / "sh").mkdir()
            (repository / "scripts" / "sh" / "install-linux.sh").write_text(
                "#!/bin/sh\n",
                encoding="utf-8",
            )
            self._git(repository, "add", ".")
            self._git(repository, "commit", "-m", "add linux installer")
            head_sha = self._git(repository, "rev-parse", "HEAD")

            completed, output_path, runner_temp = self._run_action_script(
                repository,
                base_sha=base_sha,
                head_sha=head_sha,
                run_all=False,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertEqual(
                self._read_outputs(output_path),
                {name: name in {"linux", "contract"} for name in OUTPUTS},
            )
            self.assertEqual(
                (runner_temp / "ci-changed-paths.txt").read_text(encoding="utf-8"),
                "scripts/sh/install-linux.sh\n",
            )

    def test_run_all_mode_invokes_the_detector_all_flag(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            repository = self._make_test_repository(Path(temporary_directory))

            completed, output_path, runner_temp = self._run_action_script(
                repository,
                base_sha="unused-base",
                head_sha="unused-head",
                run_all=True,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertEqual(self._read_outputs(output_path), dict.fromkeys(OUTPUTS, True))
            self.assertFalse((runner_temp / "ci-changed-paths.txt").exists())

    def test_deleted_linux_path_keeps_linux_enabled(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            repository = self._make_test_repository(Path(temporary_directory))
            base_sha = self._commit_linux_installer(repository)
            (repository / "scripts" / "sh" / "install-linux.sh").unlink()
            self._git(repository, "add", "-A")
            self._git(repository, "commit", "-m", "delete linux installer")
            head_sha = self._git(repository, "rev-parse", "HEAD")

            completed, output_path, runner_temp = self._run_action_script(
                repository,
                base_sha=base_sha,
                head_sha=head_sha,
                run_all=False,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertTrue(self._read_outputs(output_path)["linux"])
            self.assertEqual(
                (runner_temp / "ci-changed-paths.txt").read_text(encoding="utf-8"),
                "scripts/sh/install-linux.sh\n",
            )

    def test_renaming_linux_path_out_keeps_its_old_path_and_linux_enabled(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            repository = self._make_test_repository(Path(temporary_directory))
            base_sha = self._commit_linux_installer(repository)
            self._git(
                repository,
                "mv",
                "scripts/sh/install-linux.sh",
                "renamed-installer.sh",
            )
            self._git(repository, "commit", "-m", "rename linux installer")
            head_sha = self._git(repository, "rev-parse", "HEAD")

            completed, output_path, runner_temp = self._run_action_script(
                repository,
                base_sha=base_sha,
                head_sha=head_sha,
                run_all=False,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertTrue(self._read_outputs(output_path)["linux"])
            self.assertEqual(
                set((runner_temp / "ci-changed-paths.txt").read_text(encoding="utf-8").splitlines()),
                {"renamed-installer.sh", "scripts/sh/install-linux.sh"},
            )

    def test_type_change_keeps_linux_enabled(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            repository = self._make_test_repository(Path(temporary_directory))
            base_sha = self._commit_linux_installer(repository)
            (repository / "scripts" / "sh" / "install-linux.sh").unlink()
            (repository / "scripts" / "sh" / "install-linux.sh").symlink_to("../target")
            self._git(repository, "add", "-A")
            self._git(repository, "commit", "-m", "change linux installer type")
            head_sha = self._git(repository, "rev-parse", "HEAD")

            completed, output_path, runner_temp = self._run_action_script(
                repository,
                base_sha=base_sha,
                head_sha=head_sha,
                run_all=False,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertTrue(self._read_outputs(output_path)["linux"])
            self.assertEqual(
                (runner_temp / "ci-changed-paths.txt").read_text(encoding="utf-8"),
                "scripts/sh/install-linux.sh\n",
            )

    def _section(self, name: str) -> str:
        lines = self.action.splitlines()
        try:
            start = lines.index(f"{name}:")
        except ValueError:
            return ""

        end = len(lines)
        for index in range(start + 1, len(lines)):
            if lines[index] and not lines[index].startswith(" "):
                end = index
                break
        return "\n".join(lines[start:end])

    def _top_level_keys(self, section: str) -> set[str]:
        return {
            line.strip()[:-1]
            for line in self._section(section).splitlines()
            if line.startswith("  ")
            and not line.startswith("    ")
            and line.strip().endswith(":")
        }

    def _run_script(self) -> str:
        lines = self.action.splitlines()
        marker = "      run: |"
        self.assertIn(marker, lines)
        start = lines.index(marker) + 1
        script_lines: list[str] = []
        for line in lines[start:]:
            if line and not line.startswith("        "):
                break
            script_lines.append(line[8:] if line else "")
        return "\n".join(script_lines) + "\n"

    def _make_test_repository(self, temporary_directory: Path) -> Path:
        repository = temporary_directory / "repository"
        repository.mkdir()
        (repository / "scripts" / "python").mkdir(parents=True)
        (repository / "ci").mkdir()
        shutil.copy2(DETECTOR_PATH, repository / "scripts" / "python" / DETECTOR_PATH.name)
        shutil.copy2(MANIFEST_PATH, repository / "ci" / MANIFEST_PATH.name)
        (repository / "README.md").write_text("fixture\n", encoding="utf-8")
        self._git(repository, "init", "-q")
        self._git(repository, "config", "user.email", "ci@example.test")
        self._git(repository, "config", "user.name", "CI Test")
        self._git(repository, "add", ".")
        self._git(repository, "commit", "-m", "initial")
        return repository

    def _commit_linux_installer(self, repository: Path) -> str:
        (repository / "scripts" / "sh").mkdir(parents=True)
        (repository / "scripts" / "sh" / "install-linux.sh").write_text(
            "#!/bin/sh\n",
            encoding="utf-8",
        )
        self._git(repository, "add", ".")
        self._git(repository, "commit", "-m", "add linux installer")
        return self._git(repository, "rev-parse", "HEAD")

    def _run_action_script(
        self,
        repository: Path,
        *,
        base_sha: str,
        head_sha: str,
        run_all: bool,
    ) -> tuple[subprocess.CompletedProcess[str], Path, Path]:
        temporary_directory = repository.parent
        runner_temp = temporary_directory / "runner-temp"
        runner_temp.mkdir()
        output_path = temporary_directory / "github-output.txt"
        python_bin = temporary_directory / "bin"
        python_bin.mkdir()
        (python_bin / "python").symlink_to(sys.executable)

        environment = os.environ.copy()
        environment.update(
            {
                "BASE_SHA": base_sha,
                "HEAD_SHA": head_sha,
                "RUN_ALL": "true" if run_all else "false",
                "RUNNER_TEMP": str(runner_temp),
                "GITHUB_OUTPUT": str(output_path),
                "PATH": f"{python_bin}{os.pathsep}{environment['PATH']}",
            }
        )
        completed = subprocess.run(
            ["bash", "-c", self._run_script()],
            check=False,
            cwd=repository,
            env=environment,
            capture_output=True,
            text=True,
        )
        return completed, output_path, runner_temp

    @staticmethod
    def _read_outputs(output_path: Path) -> dict[str, bool]:
        return {
            name: value == "true"
            for name, value in (
                line.split("=", maxsplit=1)
                for line in output_path.read_text(encoding="utf-8").splitlines()
            )
        }

    @staticmethod
    def _git(
        repository: Path,
        *arguments: str,
    ) -> str:
        completed = subprocess.run(
            ["git", *arguments],
            check=True,
            cwd=repository,
            capture_output=True,
            text=True,
        )
        return completed.stdout.strip()


if __name__ == "__main__":
    unittest.main()
