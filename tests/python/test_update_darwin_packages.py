"""Tests for the Darwin package update and provider-promotion helper."""

from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "python" / "update_darwin_packages.py"
REGISTRY = ROOT / "nix" / "packages" / "darwin-provider-candidates.nix"


def load_module():
    spec = importlib.util.spec_from_file_location("update_darwin_packages", SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load {SCRIPT}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class UpdateDarwinPackagesTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.updater = load_module()

    def test_registry_has_only_explicit_reviewed_candidates(self) -> None:
        registry = self.updater.load_candidate_registry(REGISTRY)
        self.assertEqual(
            set(registry), {"dia-browser", "orca-editor", "hammerspoon", "docker-desktop"}
        )
        for package in registry.values():
            self.assertNotIn("dia", package.candidates)
            self.assertNotIn("orca", package.candidates)

    def test_only_explicit_attrs_are_evaluated(self) -> None:
        runner = self.updater.RecordingNixRunner()
        result = self.updater.evaluate_candidates(
            {"hammerspoon": self.updater.Candidate("hammerspoon", "hammerspoon")},
            runner,
        )
        self.assertEqual(set(result), {"hammerspoon"})
        self.assertEqual(runner.evaluated, ["hammerspoon"])

    def test_build_or_identity_failure_keeps_custom_source_and_reason(self) -> None:
        runner = self.updater.RecordingNixRunner(build_error="identity mismatch")
        current = self.updater.RegistryEntry(
            source="custom", nix_attr=None, candidates=("hammerspoon",)
        )
        result = self.updater.try_promote(
            "hammerspoon", current, "hammerspoon", runner
        )
        self.assertEqual(result.entry, current)
        self.assertEqual(result.reason, "identity mismatch")
        self.assertFalse(result.promoted)

    def test_custom_update_changes_only_version_url_and_hash_literals(self) -> None:
        original = """stdenvNoCC.mkDerivation {
  pname = \"demo\";
  version = \"1.0\";
  src = fetchurl {
    url = \"https://example.invalid/demo-1.0.zip\";
    hash = \"sha256-old\";
  };
  meta = { homepage = \"https://example.invalid\"; };
}
"""
        updated = self.updater.update_derivation_literals(
            original,
            version="2.0",
            url="https://example.invalid/demo-2.0.zip",
            hash_value="sha256-new",
        )
        self.assertEqual(
            updated.replace('version = "2.0"', 'version = "1.0"')
            .replace('url = "https://example.invalid/demo-2.0.zip"', 'url = "https://example.invalid/demo-1.0.zip"')
            .replace('hash = "sha256-new"', 'hash = "sha256-old"'),
            original,
        )

    def test_empty_update_is_byte_identical(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "darwin-package-update.json"
            before = json.dumps({"updates": [], "promotions": []}, indent=2) + "\n"
            path.write_text(before, encoding="utf-8")
            self.updater.write_report(path, {"updates": [], "promotions": []})
            self.assertEqual(path.read_bytes(), before.encode())


if __name__ == "__main__":
    unittest.main()
