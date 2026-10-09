"""Runtime contracts for the build-local Hermes test fixture."""

from __future__ import annotations

import json
import os
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import yaml

try:
    from build_fixture import private_fixture
except ModuleNotFoundError as error:
    if error.name != "build_fixture":
        raise
    private_fixture = None

HOME_MARKER = "/__hermes_bootstrap_test_home__"


class BuildFixtureTests(unittest.TestCase):
    def setUp(self) -> None:
        self.assertIsNotNone(private_fixture, "build-local fixture lifecycle is missing")
        self.temporary = tempfile.TemporaryDirectory(prefix="hermes fixture ' ")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.template = self.root / "manifest-template.yaml"
        self.template.write_text(
            f"data_root: {HOME_MARKER}\nmanaged_target: {HOME_MARKER}/profiles/rick\n",
            encoding="utf-8",
        )
        self.cli = self.root / "read-binding"
        self.cli.write_text(
            f"#!{sys.executable}\n"
            "import json, os\n"
            "from pathlib import Path\n"
            "print(json.dumps({'home': os.environ['HERMES_HOME'], "
            "'manifest': Path(os.environ['HERMES_BOOTSTRAP_MANIFEST']).read_text(), "
            "'ambient_home': os.environ['HOME'], 'arguments': __import__('sys').argv[1:]}))\n",
            encoding="utf-8",
        )
        self.cli.chmod(0o700)

    def test_binding_is_canonical_private_and_survives_minimal_child_environment(self) -> None:
        alias = self.root / "temporary-alias"
        alias.symlink_to(self.root, target_is_directory=True)
        with private_fixture(self.template, self.cli, alias, "/bin/sh") as fixture:
            self.assertEqual(fixture.root.parent, self.root)
            self.assertEqual(fixture.home.resolve(), fixture.home)
            self.assertEqual(fixture.home.stat().st_uid, os.geteuid())
            self.assertEqual(stat.S_IMODE(fixture.home.stat().st_mode), 0o700)
            result = subprocess.run(
                [str(fixture.executable), "sync-profiles", "argument with spaces"],
                env={"HOME": "/nonexistent", "PATH": "/usr/bin:/bin"},
                capture_output=True,
                text=True,
                check=True,
                timeout=10,
            )
            self.assertEqual(
                json.loads(result.stdout),
                {
                    "home": str(fixture.home),
                    "manifest": f"data_root: {fixture.home}\nmanaged_target: {fixture.home}/profiles/rick\n",
                    "ambient_home": "/nonexistent",
                    "arguments": ["sync-profiles", "argument with spaces"],
                },
            )
        self.assertFalse(fixture.root.exists())
        self.assertTrue(self.template.exists())

    def test_independent_fixture_cleanup_cannot_remove_the_other_fixture(self) -> None:
        first_context = private_fixture(self.template, self.cli, self.root, "/bin/sh")
        first = first_context.__enter__()
        try:
            with private_fixture(self.template, self.cli, self.root, "/bin/sh") as second:
                self.assertNotEqual(first.home, second.home)
                retained = second.home / "retained"
                retained.write_bytes(b"second fixture")
                first_context.__exit__(None, None, None)
                self.assertFalse(first.root.exists())
                self.assertEqual(retained.read_bytes(), b"second fixture")
                self.assertTrue(second.executable.is_file())
            self.assertFalse(second.root.exists())
        finally:
            first_context.__exit__(None, None, None)

    def test_invalid_template_fails_and_cleans_only_its_allocated_directory(self) -> None:
        self.template.write_text("data_root: /unexpected\n", encoding="utf-8")
        before = set(self.root.iterdir())
        with self.assertRaisesRegex(ValueError, "home marker"):
            with private_fixture(self.template, self.cli, self.root, "/bin/sh"):
                self.fail("unbound template accepted")
        self.assertEqual(set(self.root.iterdir()), before)

    def test_runner_propagates_child_failure_and_cleans_its_private_fixture(self) -> None:
        before = set(self.root.iterdir())
        result = subprocess.run(
            [
                sys.executable,
                str(Path(__file__).with_name("build_fixture.py")),
                "--manifest-template", str(self.template),
                "--bootstrap-cli", str(self.cli),
                "--temporary-root", str(self.root),
                "--shell", "/bin/sh",
                "--", sys.executable, "-c",
                "import os, subprocess, sys; "
                "subprocess.run([os.environ['DOTFILES_HERMES_BOOTSTRAP_EXECUTABLE']], check=True); "
                "sys.exit(47)",
            ],
            env={"HOME": "/nonexistent", "PATH": "/usr/bin:/bin", "TMPDIR": "/nonexistent"},
            capture_output=True,
            text=True,
            check=False,
            timeout=10,
        )
        self.assertEqual(result.returncode, 47, result.stderr)
        binding = json.loads(result.stdout)
        self.assertEqual(binding["ambient_home"], "/nonexistent")
        self.assertEqual(Path(binding["home"]).parent.parent, self.root)
        self.assertFalse(Path(binding["home"]).exists())
        self.assertEqual(set(self.root.iterdir()), before)

    def test_ssot_manifest_paths_and_semantics_survive_yaml_sensitive_build_parent(self) -> None:
        source = Path(__file__).resolve().parents[3] / "nix/modules/hermes-agent/manifest.yaml"
        template = self.root / "ssot-template.yaml"
        template.write_text(
            source.read_text(encoding="utf-8").replace("/opt/data", HOME_MARKER),
            encoding="utf-8",
        )
        parent = self.root / "build # quoted : parent"
        parent.mkdir()
        with private_fixture(template, self.cli, parent, "/bin/sh") as fixture:
            parsed = yaml.safe_load(fixture.manifest.read_text(encoding="utf-8"))
            self.assertEqual(parsed["data_root"], str(fixture.home))
            self.assertEqual(parsed["root_distribution"]["target"], str(fixture.home))
            expected = yaml.safe_load(template.read_text(encoding="utf-8"))
            expected["data_root"] = str(fixture.home)
            expected["root_distribution"]["target"] = str(fixture.home)
            for entry in (*expected["profiles"], *expected["shared_repositories"]):
                for key in ("target", "legacy_target"):
                    if key in entry:
                        suffix = Path(entry[key]).relative_to(HOME_MARKER)
                        entry[key] = str(fixture.home / suffix)
            self.assertEqual(parsed, expected)


if __name__ == "__main__":
    unittest.main()
