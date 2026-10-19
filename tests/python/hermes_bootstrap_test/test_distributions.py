from __future__ import annotations

import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


BOOTSTRAP_ROOT = Path(__file__).resolve().parents[3] / "scripts" / "python"
sys.path.insert(0, str(BOOTSTRAP_ROOT))

from hermes_bootstrap.distributions import (
    apply_profile_distribution,
    apply_root_distribution,
)
from hermes_bootstrap.errors import ApplyError
from hermes_bootstrap.git import StagedSource
from hermes_bootstrap.models import DistributionSource


class DistributionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.data_root = self.root / "data"
        self.data_root.mkdir()
        self.stage_root = self.root / "stage"
        self.stage_root.mkdir()

    def source(self, name: str, *, root: bool = False) -> StagedSource:
        declaration = DistributionSource(
            name,
            f"https://github.com/rurusasu/hermes-profile-{'alfred' if root else name}.git",
            "main",
            self.data_root if root else self.data_root / "profiles" / name,
            "root-distribution.yaml" if root else "distribution.yaml",
        )
        return StagedSource(declaration, self.stage_root, "a" * 40)

    def write_root_manifest(self, owned: list[str], **overrides: object) -> None:
        data: dict[str, object] = {
            "schema_version": 1,
            "name": "default",
            "version": "0.1.0",
            "hermes_requires": ">=0.18.2",
            "distribution_owned": owned,
        }
        data.update(overrides)
        self.write_yaml(self.stage_root / "root-distribution.yaml", data)

    def write_profile_manifest(self, profile_name: str, owned: list[str], **overrides: object) -> None:
        data: dict[str, object] = {
            "name": profile_name,
            "version": "0.1.0",
            "hermes_requires": ">=0.18.2",
            "distribution_owned": owned,
        }
        data.update(overrides)
        self.write_yaml(self.stage_root / "distribution.yaml", data)

    def write_yaml(self, path: Path, data: dict[str, object]) -> None:
        import yaml

        path.write_text(yaml.safe_dump(data, sort_keys=False), encoding="utf-8")

    def test_root_file_replace_failure_preserves_the_original_and_can_retry(self) -> None:
        (self.stage_root / "config.yaml").write_text("new config\n", encoding="utf-8")
        self.write_root_manifest(["config.yaml"])
        target = self.data_root / "config.yaml"
        target.write_text("old config\n", encoding="utf-8")
        original_replace = os.replace

        def fail_install(source: object, destination: object) -> None:
            if destination == target:
                raise OSError("install-secret-marker")
            original_replace(source, destination)

        with mock.patch("hermes_bootstrap.distributions.os.replace", side_effect=fail_install):
            with self.assertRaises(ApplyError) as caught:
                apply_root_distribution(self.source("default", root=True), self.data_root)

        self.assertEqual(target.read_text(encoding="utf-8"), "old config\n")
        self.assertEqual(list(self.data_root.glob(".config.yaml.bootstrap-*")), [])
        self.assert_exception_hides_markers(caught.exception, "install-secret-marker", str(self.stage_root))

        apply_root_distribution(self.source("default", root=True), self.data_root)
        self.assertEqual(target.read_text(encoding="utf-8"), "new config\n")

    def test_profile_preserves_an_existing_user_profile(self) -> None:
        (self.stage_root / "config.yaml").write_text("staged config\n", encoding="utf-8")
        self.write_profile_manifest("rick", ["config.yaml"])
        target = self.data_root / "profiles" / "rick"
        (target / "memories").mkdir(parents=True)
        original = {
            "config.yaml": b"local config\n",
            "memories/keep": b"user data\n",
            ".env": b"local secret\n",
        }
        for name, content in original.items():
            (target / name).write_bytes(content)

        with self.assertRaises(ApplyError):
            apply_profile_distribution(self.source("rick"), self.data_root)

        self.assertEqual({name: (target / name).read_bytes() for name in original}, original)

    def test_initial_install_under_native_home_preserves_existing_profiles(self) -> None:
        (self.stage_root / "config.yaml").write_bytes(b"model: example\n")
        (self.stage_root / ".github").mkdir()
        (self.stage_root / ".github" / "workflow.yml").write_bytes(b"unowned\n")
        (self.stage_root / "unlisted.txt").write_bytes(b"not distribution-owned\n")
        self.write_profile_manifest("rick", ["config.yaml"])
        other = self.data_root / "profiles" / "local"
        other.mkdir(parents=True)
        (other / "notes.md").write_bytes(b"user data\n")

        with (
            mock.patch.dict(os.environ, {"HERMES_HOME": str(self.data_root)}),
            mock.patch("hermes_constants._get_platform_default_hermes_home", return_value=self.data_root),
        ):
            apply_profile_distribution(self.source("rick"), self.data_root)
            self.assertEqual(os.environ["HERMES_HOME"], str(self.data_root))

        target = self.data_root / "profiles" / "rick"
        self.assertEqual((target / "config.yaml").read_bytes(), b"model: example\n")
        self.assertFalse((target / ".github").exists())
        self.assertFalse((target / "unlisted.txt").exists())
        self.assertEqual((other / "notes.md").read_bytes(), b"user data\n")
        manifest = (target / "distribution.yaml").read_text(encoding="utf-8")
        self.assertIn("source: https://github.com/rurusasu/hermes-profile-rick.git", manifest)
        self.assertNotIn(str(self.stage_root), manifest)

    def test_profile_failed_private_install_is_cleaned_and_can_retry(self) -> None:
        (self.stage_root / "config.yaml").write_text("config\n", encoding="utf-8")
        self.write_profile_manifest("rick", ["config.yaml"])
        previous_home = os.environ.pop("HERMES_HOME", None)
        self.addCleanup(self.restore_environment, "HERMES_HOME", previous_home)
        private_homes: list[Path] = []

        def fail_after_partial_install(*args: object, **kwargs: object) -> None:
            private_home = Path(os.environ["HERMES_HOME"])
            private_homes.append(private_home)
            partial = private_home / "profiles" / "rick"
            partial.mkdir(parents=True)
            (partial / "config.yaml").write_bytes(b"partial profile\n")
            raise RuntimeError("staged-secret-marker")

        with mock.patch("hermes_bootstrap.distributions.profile_distribution.install_distribution", side_effect=fail_after_partial_install):
            with self.assertRaises(ApplyError) as caught:
                apply_profile_distribution(self.source("rick"), self.data_root)

        self.assertNotIn("HERMES_HOME", os.environ)
        self.assertEqual(str(caught.exception), "could not apply the named profile distribution")
        self.assert_exception_hides_markers(caught.exception, "staged-secret-marker", str(self.stage_root))
        self.assertFalse((self.data_root / "profiles").exists())
        self.assertEqual(len(private_homes), 1)
        self.assertFalse(private_homes[0].exists())

        apply_profile_distribution(self.source("rick"), self.data_root)

        self.assertNotIn("HERMES_HOME", os.environ)
        self.assertEqual((self.data_root / "profiles" / "rick" / "config.yaml").read_bytes(), b"config\n")

    def restore_environment(self, key: str, value: str | None) -> None:
        if value is None:
            os.environ.pop(key, None)
        else:
            os.environ[key] = value

    def assert_exception_hides_markers(self, error: BaseException, *markers: str) -> None:
        for marker in markers:
            self.assertNotIn(marker, str(error))


if __name__ == "__main__":
    unittest.main()
