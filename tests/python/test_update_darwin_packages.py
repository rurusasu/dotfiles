"""Tests for the Darwin package update and provider-promotion helper."""

from __future__ import annotations

import importlib.util
import contextlib
import io
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


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
            set(registry), {"dia-browser", "orca-editor", "hammerspoon"}
        )
        for package in registry.values():
            self.assertNotIn("dia", package.candidates)
            self.assertNotIn("orca", package.candidates)

    def test_docker_desktop_is_not_a_custom_darwin_update_profile(self) -> None:
        self.assertNotIn("docker-desktop", self.updater.DERIVATIONS)
        self.assertNotIn("docker-desktop", self.updater.PROFILES)
        self.assertNotIn("docker-desktop", self.updater.IDENTITIES)

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

    def test_orca_uses_arm64_dmg_even_when_zip_is_first(self) -> None:
        payload = json.dumps({"tag_name": "v1.4.198", "assets": [
            {"browser_download_url": "https://github.com/stablyai/orca/releases/download/v1.4.198/Orca-1.4.198-arm64-mac.zip"},
            {"browser_download_url": "https://github.com/stablyai/orca/releases/download/v1.4.198/orca-macos-x64.dmg"},
            {"browser_download_url": "https://github.com/stablyai/orca/releases/download/v1.4.198/orca-macos-arm64.dmg"},
        ]}).encode()
        release = self.updater.PROFILES["orca-editor"].parse_release(payload)
        self.assertEqual(release.version, "1.4.198")
        self.assertEqual(release.url, "https://github.com/stablyai/orca/releases/download/v1.4.198/orca-macos-arm64.dmg")

    def test_orca_missing_dmg_is_an_update_error_not_an_x64_fallback(self) -> None:
        payload = json.dumps({"tag_name": "v9.0", "assets": [
            {"browser_download_url": "https://github.com/stablyai/orca/releases/download/v9.0/orca-macos-x64.dmg"},
        ]}).encode()
        with patch.object(self.updater, "prefetch_hash", return_value="sha256-test"):
            updates = self.updater.collect_updates(["orca-editor"], fetcher=lambda _: payload)
        self.assertEqual(updates[0]["status"], "error")

    def test_release_fetch_authenticates_only_github_api(self) -> None:
        requests = []
        def open_request(request, **kwargs):
            requests.append(request)
            return io.BytesIO(b"{}")
        with patch.dict(os.environ, {"GH_TOKEN": "test-token", "GITHUB_TOKEN": "other-token"}), patch.object(self.updater.urllib.request.OpenerDirector, "open", side_effect=open_request):
            self.updater.fetch("https://api.github.com/repos/stablyai/orca/releases/latest")
            self.updater.fetch("https://releases.diabrowser.com/BoostBrowser-updates.xml")
        self.assertEqual(requests[0].get_header("Authorization"), "Bearer test-token")
        self.assertIsNone(requests[1].get_header("Authorization"))

    def test_partial_update_error_fails_without_changing_derivations(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "default.nix"
            original = 'version = "1";\nurl = "https://example.invalid/1.zip";\nhash = "sha256-old";\n'
            target.write_text(original)
            report = Path(directory) / "report.json"
            updates = [
                {"package": "dia-browser", "status": "update-available", "version": "2", "url": "https://example.invalid/2.zip", "hash": "sha256-new"},
                {"package": "orca-editor", "status": "error", "reason": "HTTP 403"},
            ]
            with patch.object(self.updater, "collect_updates", return_value=updates), patch.dict(self.updater.DERIVATIONS, {"dia-browser": target}), contextlib.redirect_stdout(io.StringIO()):
                status = self.updater.main(["--write", "--output", str(report)])
            self.assertNotEqual(status, 0)
            self.assertEqual(target.read_text(), original)
            self.assertEqual(json.loads(report.read_text())["updates"][1]["status"], "error")

    def test_fetch_does_not_forward_authentication_across_redirect_origins(self) -> None:
        handler = self.updater.ReleaseRedirectHandler()
        request = self.updater.urllib.request.Request(
            "https://api.github.com/repos/old/repo/releases/latest",
            headers={"Authorization": "Bearer test-token"},
        )
        for url, expected in (
            ("https://api.github.com/repos/new/repo/releases/latest", "Bearer test-token"),
            ("https://example.invalid/feed", None),
            ("http://api.github.com/feed", None),
        ):
            with self.subTest(url=url):
                redirected = handler.redirect_request(request, None, 302, "Found", {}, url)
                self.assertEqual(redirected.get_header("Authorization"), expected)


if __name__ == "__main__":
    unittest.main()
