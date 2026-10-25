"""Contracts for the local composite action that routes CI changes."""

from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
ACTION_PATH = (
    REPOSITORY_ROOT / ".github" / "actions" / "detect-ci-changes" / "action.yml"
)
OUTPUTS = {"nix", "chezmoi", "other", "linux", "darwin", "wsl", "windows"}
UNIX = {"nix", "linux", "darwin", "wsl"}


class DetectCiActionContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.action = (
            ACTION_PATH.read_text(encoding="utf-8") if ACTION_PATH.is_file() else ""
        )

    def test_non_all_mode_classifies_git_paths_and_rejects_invalid_revisions(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            repository = self._make_test_repository(Path(temporary_directory))
            base_sha = self._git(repository, "rev-parse", "HEAD")
            (repository / "nix").mkdir()
            (repository / "nix" / "example.nix").write_text(
                "#!/bin/sh\n",
                encoding="utf-8",
            )
            self._git(repository, "add", ".")
            self._git(repository, "commit", "-m", "add linux installer")
            head_sha = self._git(repository, "rev-parse", "HEAD")

            for base in (base_sha, "0" * 40):
                with self.subTest(base=base):
                    completed, output_path, runner_temp = self._run_action_script(
                        repository,
                        base_sha=base,
                        head_sha=head_sha,
                        run_all=False,
                    )

                    self.assertEqual(completed.returncode, 0, completed.stderr)
                    self.assertEqual(
                        self._read_outputs(output_path),
                        {name: name in UNIX for name in OUTPUTS},
                    )
                    self.assertEqual(
                        (runner_temp / "ci-changed-paths").read_text(encoding="utf-8"),
                        "README.md\0nix/example.nix\0"
                        if base == "0" * 40
                        else "nix/example.nix\0",
                    )

            for base, head in (("missing-base", head_sha), (base_sha, "missing-head")):
                with self.subTest(base=base, head=head):
                    completed, output_path, _ = self._run_action_script(
                        repository, base_sha=base, head_sha=head, run_all=False
                    )
                    self.assertNotEqual(completed.returncode, 0)
                    self.assertEqual(self._read_outputs(output_path), {})

        cases = (
            (("chezmoi/config.tmpl",), {"chezmoi", "windows"}),
            (("nix/modules/aerospace/default.nix",), {"nix", "darwin"}),
            (("nix/modules/1password/op-ssh-sign-wsl",), {"nix", "wsl"}),
            (("nix/modules/editors/vscode.nix",), {"nix", "wsl"}),
            (("nix/modules/1password/default.nix",), UNIX),
            (
                ("nix/modules/fonts/wsl-fontconfig.conf",),
                {"nix", "wsl", "chezmoi", "windows"},
            ),
            (
                ("nix/defaults.nix",),
                UNIX | {"chezmoi", "windows"},
            ),
            (
                ("nix/home/keybindings/bindings.nix",),
                UNIX | {"chezmoi", "windows"},
            ),
            (
                ("nix/home/keybindings/generated.json",),
                UNIX | {"chezmoi", "windows"},
            ),
            (
                ("nix/modules/terminals/ghostty/ghostty.nix",),
                UNIX | {"chezmoi", "windows"},
            ),
            (
                ("nix/modules/terminals/ghostty/ghostty-renderer.nix",),
                UNIX | {"chezmoi", "windows"},
            ),
            (
                ("nix/modules/terminals/ghostty/ghostty-windows.nix",),
                UNIX | {"chezmoi", "windows"},
            ),
            (
                ("nix/modules/editors/nvim/neovim.nix",),
                UNIX | {"chezmoi", "windows"},
            ),
            (("nix/modules/hyprland/hyprland-renderer.nix",), {"nix", "linux"}),
            (("windows/winget/packages.json",), {"nix", "chezmoi", "windows"}),
            (("scripts/sh/install-macos.sh",), OUTPUTS),
            ((".github/workflows/ci-chezmoi.yml",), OUTPUTS),
            (("taskfiles/hermes/taskfile.yml",), OUTPUTS),
            (("README.md", "docs/architecture.md", "nix/hosts/AGENTS.md"), set()),
            (("chezmoi/prompt.md",), {"chezmoi", "windows"}),
            (("chezmoi/dot_codex/AGENTS.md",), {"chezmoi", "windows"}),
            (("nix/modules/shells/bash/bashrc",), UNIX),
            (("config/other.json",), {"other"}),
            (
                ("nix/odd\n name.nix", "chezmoi/config.tmpl"),
                UNIX | {"chezmoi", "windows"},
            ),
        )
        for paths, categories in cases:
            with self.subTest(paths=paths), tempfile.TemporaryDirectory() as temporary:
                repository = self._make_test_repository(Path(temporary))
                base_sha = self._git(repository, "rev-parse", "HEAD")
                for path in paths:
                    target = repository / path
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_text("changed\n", encoding="utf-8")
                self._git(repository, "add", ".")
                self._git(repository, "commit", "-m", "change classified paths")
                head_sha = self._git(repository, "rev-parse", "HEAD")
                completed, output_path, _ = self._run_action_script(
                    repository, base_sha=base_sha, head_sha=head_sha, run_all=False
                )
                self.assertEqual(completed.returncode, 0, completed.stderr)
                self.assertEqual(
                    self._read_outputs(output_path),
                    {name: name in categories for name in OUTPUTS},
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
            self.assertEqual(
                self._read_outputs(output_path), dict.fromkeys(OUTPUTS, True)
            )
            self.assertFalse((runner_temp / "ci-changed-paths").exists())

    def test_deleted_linux_path_keeps_linux_enabled(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            repository = self._make_test_repository(Path(temporary_directory))
            base_sha = self._commit_nix_config(repository)
            (repository / "nix" / "example.nix").unlink()
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
            self.assertTrue(self._read_outputs(output_path)["nix"])
            self.assertEqual(
                (runner_temp / "ci-changed-paths").read_text(encoding="utf-8"),
                "nix/example.nix\0",
            )

    def test_renaming_linux_path_out_keeps_its_old_path_and_linux_enabled(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            repository = self._make_test_repository(Path(temporary_directory))
            base_sha = self._commit_nix_config(repository)
            self._git(
                repository,
                "mv",
                "nix/example.nix",
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
            self.assertTrue(self._read_outputs(output_path)["nix"])
            self.assertEqual(
                set(
                    (runner_temp / "ci-changed-paths")
                    .read_text(encoding="utf-8")
                    .split("\0")[:-1]
                ),
                {"renamed-installer.sh", "nix/example.nix"},
            )

    def test_type_change_keeps_linux_enabled(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            repository = self._make_test_repository(Path(temporary_directory))
            base_sha = self._commit_nix_config(repository)
            (repository / "nix" / "example.nix").unlink()
            (repository / "nix" / "example.nix").symlink_to("../target")
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
            self.assertTrue(self._read_outputs(output_path)["nix"])
            self.assertEqual(
                (runner_temp / "ci-changed-paths").read_text(encoding="utf-8"),
                "nix/example.nix\0",
            )

    def test_pull_request_ignores_changes_only_on_the_base_branch(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            repository = self._make_test_repository(Path(temporary_directory))
            self._git(repository, "branch", "pull-request")
            (repository / "chezmoi").mkdir()
            (repository / "chezmoi/base.tmpl").write_text("base change\n")
            self._git(repository, "add", ".")
            self._git(repository, "commit", "-m", "advance base with macOS change")
            base_sha = self._git(repository, "rev-parse", "HEAD")
            self._git(repository, "switch", "pull-request")
            head_sha = self._commit_nix_config(repository)

            completed, output_path, _ = self._run_action_script(
                repository,
                base_sha=base_sha,
                head_sha=head_sha,
                run_all=False,
                event_name="pull_request",
            )

            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertTrue(self._read_outputs(output_path)["nix"])
            self.assertFalse(self._read_outputs(output_path)["chezmoi"])

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
        (repository / "README.md").write_text("fixture\n", encoding="utf-8")
        self._git(repository, "init", "-q")
        self._git(repository, "config", "user.email", "ci@example.test")
        self._git(repository, "config", "user.name", "CI Test")
        self._git(repository, "add", ".")
        self._git(repository, "commit", "-m", "initial")
        return repository

    def _commit_nix_config(self, repository: Path) -> str:
        (repository / "nix").mkdir(parents=True)
        (repository / "nix" / "example.nix").write_text(
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
        event_name: str = "push",
    ) -> tuple[subprocess.CompletedProcess[str], Path, Path]:
        temporary_directory = repository.parent
        runner_temp = temporary_directory / "runner-temp"
        runner_temp.mkdir(exist_ok=True)
        output_path = temporary_directory / "github-output.txt"
        output_path.write_text("", encoding="utf-8")

        environment = os.environ.copy()
        environment.update(
            {
                "GITHUB_EVENT_NAME": event_name,
                "BASE_SHA": base_sha,
                "HEAD_SHA": head_sha,
                "RUN_ALL": "true" if run_all else "false",
                "RUNNER_TEMP": str(runner_temp),
                "GITHUB_OUTPUT": str(output_path),
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
