"""Install provider code from the catalog shipped by the Hermes runtime."""

from __future__ import annotations

import importlib.util
import subprocess
import tempfile
import unittest
from pathlib import Path

import yaml

MODULE_PATH = Path(__file__).resolve().parents[2] / "install_memory_provider.py"


class MemoryProviderInstallTests(unittest.TestCase):
    def setUp(self) -> None:
        spec = importlib.util.spec_from_file_location(
            "memory_provider_install", MODULE_PATH
        )
        assert spec is not None and spec.loader is not None
        self.installer = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.installer)
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.hermes = self.root / "hermes"

    def git(self, repository: Path, *args: str) -> str:
        return subprocess.check_output(
            ["git", "-C", str(repository), *args], text=True
        ).strip()

    def catalog(self, **entry: str) -> None:
        directory = self.hermes / "plugin-catalog"
        directory.mkdir(parents=True)
        (directory / "hindsight.yaml").write_text(yaml.safe_dump(entry))

    def test_existing_bundled_provider_needs_no_catalog_or_download(self) -> None:
        destination = self.hermes / "plugins/memory/hindsight"
        destination.mkdir(parents=True)
        (destination / "__init__.py").write_text("bundled = True\n")
        self.installer.install_provider(self.hermes, "hindsight")
        self.assertEqual((destination / "__init__.py").read_text(), "bundled = True\n")

    def test_missing_provider_installs_the_catalog_reviewed_source_not_the_repo_head(
        self,
    ) -> None:
        repository = self.root / "repository"
        repository.mkdir()
        self.git(repository, "init", "-q")
        source = repository / "integrations/hermes"
        source.mkdir(parents=True)
        (source / "__init__.py").write_text("reviewed = True\n")
        (source / "plugin.yaml").write_text("name: hindsight\n")
        self.git(repository, "add", ".")
        self.git(
            repository,
            "-c",
            "user.name=Fixture",
            "-c",
            "user.email=fixture@example.invalid",
            "commit",
            "-qm",
            "reviewed",
        )
        reviewed = self.git(repository, "rev-parse", "HEAD")
        (source / "__init__.py").write_text("reviewed = False\n")
        self.git(repository, "add", ".")
        self.git(
            repository,
            "-c",
            "user.name=Fixture",
            "-c",
            "user.email=fixture@example.invalid",
            "commit",
            "-qm",
            "unreviewed",
        )
        self.catalog(
            name="hindsight",
            repo=str(repository),
            sha=reviewed,
            subdir="integrations/hermes",
        )

        self.installer.install_provider(self.hermes, "hindsight")

        destination = self.hermes / "plugins/memory/hindsight"
        self.assertEqual((destination / "__init__.py").read_text(), "reviewed = True\n")
        self.assertEqual((destination / "plugin.yaml").read_text(), "name: hindsight\n")
        self.assertFalse((destination / ".git").exists())

    def test_missing_catalog_fails_without_creating_a_provider(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "catalog"):
            self.installer.install_provider(self.hermes, "hindsight")
        self.assertFalse((self.hermes / "plugins/memory/hindsight").exists())

    def test_declared_dependencies_are_checked_before_provider_import(self) -> None:
        destination = self.hermes / "plugins/memory/hindsight"
        destination.mkdir(parents=True)
        (destination / "__init__.py").write_text(
            "raise AssertionError('do not import')"
        )
        manifest = destination / "plugin.yaml"
        manifest.write_text("pip_dependencies: ['PyYAML>=0']\n")
        self.installer.verify_provider_dependencies(self.hermes, "hindsight")
        manifest.write_text("pip_dependencies: ['PyYAML<0']\n")
        with self.assertRaisesRegex(RuntimeError, "Provider dependency mismatch"):
            self.installer.verify_provider_dependencies(self.hermes, "hindsight")

    def test_missing_declared_distribution_fails_without_lazy_installation(
        self,
    ) -> None:
        destination = self.hermes / "plugins/memory/hindsight"
        destination.mkdir(parents=True)
        (destination / "plugin.yaml").write_text(
            "pip_dependencies: ['hermes-test-missing-distribution>=0']\n"
        )
        with self.assertRaisesRegex(RuntimeError, "Provider dependency is missing"):
            self.installer.verify_provider_dependencies(self.hermes, "hindsight")

    def test_incomplete_provider_directory_is_preserved_and_rejected(self) -> None:
        destination = self.hermes / "plugins/memory/hindsight"
        destination.mkdir(parents=True)
        marker = destination / "existing.txt"
        marker.write_text("preserve")
        with self.assertRaisesRegex(RuntimeError, "Incomplete provider"):
            self.installer.install_provider(self.hermes, "hindsight")
        self.assertEqual(marker.read_text(), "preserve")
        self.assertEqual(list(destination.iterdir()), [marker])

    def test_catalog_path_escape_fails_before_installation(self) -> None:
        self.catalog(name="hindsight", repo="unused", sha="a" * 40, subdir="../escape")
        with self.assertRaisesRegex(ValueError, "subdir"):
            self.installer.install_provider(self.hermes, "hindsight")
        self.assertFalse((self.hermes / "plugins/memory/hindsight").exists())
