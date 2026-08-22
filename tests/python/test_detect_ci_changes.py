"""Behavioral contracts for platform-aware CI path routing."""

from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
MANIFEST_PATH = REPOSITORY_ROOT / "ci" / "path-routing.json"
BOOTSTRAP_MANIFEST_PATH = REPOSITORY_ROOT / "ci" / "bootstrap-path-routing.json"
DETECTOR_PATH = REPOSITORY_ROOT / "scripts" / "python" / "detect_ci_changes.py"
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
CASES = {
    "nix/packages/sets.nix": {
        "linux",
        "darwin",
        "wsl",
        "windows",
        "contract",
        "nix",
        "chezmoi",
        "package_catalog",
    },
    "nix/home/common.nix": {
        "linux",
        "darwin",
        "wsl",
        "contract",
        "nix",
        "chezmoi",
    },
    "scripts/sh/install-linux.sh": {"linux", "contract"},
    "scripts/sh/install-macos.sh": {"darwin", "contract"},
    "install.sh": {"linux", "darwin", "contract", "devcontainer"},
    "scripts/sh/verify-environment.sh": {"linux", "darwin", "contract"},
    ".github/e2e/run-bootstrap-acceptance.sh": {"linux", "contract"},
    "scripts/sh/nixos-wsl-postinstall.sh": {
        "wsl",
        "windows",
        "contract",
        "nix",
    },
    "scripts/powershell/handlers/Handler.NixOSWSL.ps1": {
        "wsl",
        "windows",
        "contract",
    },
    "chezmoi/dot_config/nvim/init.lua": {"contract", "chezmoi"},
    "docker/hermes-xapi-mcp/Dockerfile": {
        "linux",
        "darwin",
        "wsl",
        "windows",
        "contract",
        "hermes",
    },
}
BOOTSTRAP_CASES = {
    "windows/winget/packages.json": {"windows", "contract"},
    "nix/hosts/darwin/default.nix": {"darwin", "contract", "nix"},
    "nix/hosts/linux/configuration.nix": {"linux", "contract", "nix"},
    "nix/hosts/wsl/configuration.nix": {"wsl", "contract", "nix"},
    "scripts/powershell/handlers/Handler.NixOSWSL.ps1": {"wsl", "contract"},
    "scripts/powershell/lib/SetupHandler.ps1": {"wsl", "windows", "contract"},
    "chezmoi/shells/Microsoft.PowerShell_profile.ps1": {
        "linux",
        "darwin",
        "wsl",
        "windows",
        "contract",
    },
    "nix/packages/sets.nix": {
        "linux",
        "darwin",
        "wsl",
        "windows",
        "contract",
        "nix",
    },
    "flake.nix": {"linux", "darwin", "wsl", "contract", "nix"},
    "install.sh": {"linux", "darwin", "contract"},
    ".github/workflows/ci-bootstrap.yml": {
        "linux",
        "darwin",
        "wsl",
        "windows",
        "contract",
        "nix",
    },
}


def load_detector():
    """Load the detector from its executable source path."""
    spec = importlib.util.spec_from_file_location("detect_ci_changes", DETECTOR_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load CI change detector")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class DetectCiChangesTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.detector = load_detector()

    def test_paths_route_to_the_expected_output_sets(self) -> None:
        for path, expected_enabled in CASES.items():
            with self.subTest(path=path):
                result = self.detector.route_paths([path], MANIFEST_PATH)

                self.assertEqual(set(result), OUTPUTS)
                self.assertEqual(
                    {name for name, enabled in result.items() if enabled},
                    expected_enabled,
                )

    def test_bootstrap_paths_route_to_the_expected_platform_sets(self) -> None:
        for path, expected_enabled in BOOTSTRAP_CASES.items():
            with self.subTest(path=path):
                result = self.detector.route_paths([path], BOOTSTRAP_MANIFEST_PATH)

                self.assertEqual(
                    {name for name, enabled in result.items() if enabled},
                    expected_enabled,
                )

    def test_multiple_paths_union_outputs(self) -> None:
        result = self.detector.route_paths(
            ["scripts/sh/install-linux.sh", "scripts/sh/install-macos.sh"],
            MANIFEST_PATH,
        )

        self.assertTrue(result["linux"])
        self.assertTrue(result["darwin"])

    def test_unknown_path_enables_contract_only(self) -> None:
        result = self.detector.route_paths(["README.md"], MANIFEST_PATH)

        self.assertEqual(
            {name for name, enabled in result.items() if enabled},
            {"contract"},
        )

    def test_routing_infrastructure_enables_every_output(self) -> None:
        paths = (
            "ci/path-routing.json",
            "scripts/python/detect_ci_changes.py",
            "tests/python/test_detect_ci_changes.py",
            ".github/actions/detect-ci-changes/action.yml",
            ".github/workflows/ci-contract.yml",
        )

        for path in paths:
            with self.subTest(path=path):
                result = self.detector.route_paths([path], MANIFEST_PATH)

                self.assertEqual(
                    {name for name, enabled in result.items() if enabled},
                    {
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
                    },
                )

    def test_generic_workflow_path_enables_contract_only(self) -> None:
        result = self.detector.route_paths(
            [".github/workflows/ci-unregistered.yml"],
            MANIFEST_PATH,
        )

        self.assertEqual(
            {name for name, enabled in result.items() if enabled},
            {"contract"},
        )

    def test_generic_ci_test_path_enables_contract_only(self) -> None:
        result = self.detector.route_paths(
            ["tests/bash/future-routing-contract.bats"],
            MANIFEST_PATH,
        )

        self.assertEqual(
            {name for name, enabled in result.items() if enabled},
            {"contract"},
        )

    def test_special_bats_paths_enable_contract_and_devcontainer(self) -> None:
        special_paths = ("tests/bash/install_macos.bats", "tests/bash/install_linux.bats")
        for path in special_paths:
            with self.subTest(path=path):
                result = self.detector.route_paths([path], MANIFEST_PATH)
                self.assertEqual(
                    {name for name, enabled in result.items() if enabled},
                    {"contract", "devcontainer"},
                )

        manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
        manifest["rules"] = [
            rule
            for rule in manifest["rules"]
            if set(rule["patterns"]) != set(special_paths)
        ]
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary_manifest = Path(temporary_directory) / "routing.json"
            temporary_manifest.write_text(json.dumps(manifest), encoding="utf-8")
            mutated_result = self.detector.route_paths([special_paths[0]], temporary_manifest)

        self.assertFalse(mutated_result["devcontainer"])

    def test_absolute_path_is_rejected(self) -> None:
        with self.assertRaises(ValueError):
            self.detector.route_paths(["/tmp/file"], MANIFEST_PATH)

    def test_parent_traversal_is_rejected(self) -> None:
        with self.assertRaises(ValueError):
            self.detector.route_paths(["../flake.nix"], MANIFEST_PATH)

    def test_backslash_path_is_rejected(self) -> None:
        with self.assertRaises(ValueError):
            self.detector.route_paths(["scripts\\sh\\install-linux.sh"], MANIFEST_PATH)

    def test_unknown_manifest_output_is_rejected(self) -> None:
        manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
        manifest["outputs"].append("unsupported")

        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary_manifest = Path(temporary_directory) / "routing.json"
            temporary_manifest.write_text(
                json.dumps(manifest),
                encoding="utf-8",
            )

            with self.assertRaises(ValueError):
                self.detector.route_paths(["README.md"], temporary_manifest)

    def test_boolean_manifest_version_is_rejected(self) -> None:
        manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
        manifest["version"] = True

        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary_manifest = Path(temporary_directory) / "routing.json"
            temporary_manifest.write_text(json.dumps(manifest), encoding="utf-8")

            with self.assertRaises(ValueError):
                self.detector.route_paths(["README.md"], temporary_manifest)

    def test_unknown_manifest_root_key_is_rejected(self) -> None:
        manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
        manifest["unexpected"] = []

        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary_manifest = Path(temporary_directory) / "routing.json"
            temporary_manifest.write_text(json.dumps(manifest), encoding="utf-8")

            with self.assertRaises(ValueError):
                self.detector.route_paths(["README.md"], temporary_manifest)

    def test_unknown_manifest_rule_key_is_rejected(self) -> None:
        manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
        manifest["rules"][0]["unexpected"] = []

        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary_manifest = Path(temporary_directory) / "routing.json"
            temporary_manifest.write_text(json.dumps(manifest), encoding="utf-8")

            with self.assertRaises(ValueError):
                self.detector.route_paths(["README.md"], temporary_manifest)

    def test_unsafe_manifest_patterns_fail_closed_for_the_api_and_cli(self) -> None:
        for pattern in ("", "/absolute/path", "scripts\\sh\\bad", "scripts/../bad"):
            with self.subTest(pattern=pattern), tempfile.TemporaryDirectory() as temporary_directory:
                manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
                manifest["rules"][0]["patterns"] = [pattern]
                temporary_manifest = Path(temporary_directory) / "routing.json"
                temporary_manifest.write_text(json.dumps(manifest), encoding="utf-8")

                with self.assertRaises(ValueError):
                    self.detector.route_paths(["README.md"], temporary_manifest)

                completed = self._run_cli("--manifest", str(temporary_manifest), "--all")
                self.assertEqual(completed.returncode, 2)
                self.assertIn("error:", completed.stderr)

    def test_specific_hermes_and_devcontainer_rules_precede_broad_rules(self) -> None:
        rules = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))["rules"]
        rule_index = {
            pattern: index
            for index, rule in enumerate(rules)
            for pattern in rule["patterns"]
        }

        self.assertLess(
            rule_index["scripts/powershell/handlers/Handler.HermesAgent.ps1"],
            rule_index["scripts/powershell/**"],
        )
        self.assertLess(
            rule_index["chezmoi/dot_config/devcontainer/**"],
            rule_index["chezmoi/**"],
        )

    def test_all_flag_enables_every_output(self) -> None:
        completed = self._run_cli("--manifest", str(MANIFEST_PATH), "--all")

        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertEqual(json.loads(completed.stdout), dict.fromkeys(sorted(OUTPUTS), True))

    def test_github_output_contains_lowercase_booleans(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            paths_file = Path(temporary_directory) / "paths.txt"
            github_output = Path(temporary_directory) / "github-output.txt"
            paths_file.write_text("scripts/sh/install-linux.sh\n", encoding="utf-8")

            completed = self._run_cli(
                "--manifest",
                str(MANIFEST_PATH),
                "--paths-file",
                str(paths_file),
                "--github-output",
                str(github_output),
            )

            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertEqual(
                github_output.read_text(encoding="utf-8").splitlines(),
                [
                    f"{name}={'true' if name in {'contract', 'linux'} else 'false'}"
                    for name in sorted(OUTPUTS)
                ],
            )

    def test_cli_requires_a_path_source_or_all_flag(self) -> None:
        completed = self._run_cli("--manifest", str(MANIFEST_PATH))

        self.assertEqual(completed.returncode, 2)
        self.assertIn("error:", completed.stderr)

    def test_cli_rejects_paths_file_with_all_flag(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            paths_file = Path(temporary_directory) / "paths.txt"
            paths_file.write_text("README.md\n", encoding="utf-8")

            completed = self._run_cli(
                "--manifest",
                str(MANIFEST_PATH),
                "--paths-file",
                str(paths_file),
                "--all",
            )

        self.assertEqual(completed.returncode, 2)
        self.assertIn("error:", completed.stderr)

    def test_cli_reports_unsafe_path_as_an_argument_error(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            paths_file = Path(temporary_directory) / "paths.txt"
            paths_file.write_text("/tmp/file\n", encoding="utf-8")

            completed = self._run_cli(
                "--manifest",
                str(MANIFEST_PATH),
                "--paths-file",
                str(paths_file),
            )

        self.assertEqual(completed.returncode, 2)
        self.assertIn("usage:", completed.stderr)
        self.assertIn("error:", completed.stderr)

    def test_cli_reports_malformed_manifest_as_an_argument_error(self) -> None:
        manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
        manifest["version"] = True

        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary_manifest = Path(temporary_directory) / "routing.json"
            temporary_manifest.write_text(json.dumps(manifest), encoding="utf-8")

            completed = self._run_cli("--manifest", str(temporary_manifest), "--all")

        self.assertEqual(completed.returncode, 2)
        self.assertIn("usage:", completed.stderr)
        self.assertIn("error:", completed.stderr)

    @staticmethod
    def _run_cli(*arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(DETECTOR_PATH), *arguments],
            check=False,
            cwd=REPOSITORY_ROOT,
            capture_output=True,
            text=True,
        )


if __name__ == "__main__":
    unittest.main()
