"""Tests for the Darwin package update and provider-promotion helper."""

from __future__ import annotations

import importlib.util
import base64
import contextlib
import hashlib
import http.server
import io
import json
import os
import select
import shutil
import subprocess
import sys
import tempfile
import threading
import time
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

    def test_package_context_is_visible_before_network_operations(self) -> None:
        output = io.StringIO()
        url = "https://example.invalid/demo.zip"
        def fetcher(feed):
            self.assertIn("orca-editor", output.getvalue())
            self.assertIn(feed, output.getvalue())
            return b"fixture"
        def prefetch(target):
            self.assertEqual(target, url)
            self.assertIn("9.0", output.getvalue())
            self.assertIn(url, output.getvalue())
            return "sha256-test"
        profile = self.updater.PackageProfile(
            "orca-editor", "https://example.invalid/feed",
            self.updater.DERIVATIONS["orca-editor"],
            lambda _: self.updater.Release("9.0", url),
        )
        with contextlib.redirect_stderr(output), patch.dict(self.updater.PROFILES, {"orca-editor": profile}), patch.object(self.updater, "prefetch_hash", side_effect=prefetch):
            updates = self.updater.collect_updates(["orca-editor"], fetcher=fetcher)
        self.assertEqual(updates[0]["hash"], "sha256-test")
        self.assertIn("Hash acquired", output.getvalue())

    def test_unchanged_and_failed_checks_are_reported(self) -> None:
        version = self.updater.current_literals(self.updater.DERIVATIONS["orca-editor"])[0]
        for release, failure, expected in (
            (self.updater.Release(version, "https://example.invalid/a.zip"), None, "Up to date"),
            (None, None, "No compatible release asset"),
            (None, OSError("feed unavailable"), "feed unavailable"),
            (self.updater.Release("9.0", "https://example.invalid/a.zip"), None, "download failed"),
        ):
            with self.subTest(expected=expected):
                output = io.StringIO()
                profile = self.updater.PackageProfile("orca-editor", "https://example.invalid/feed", self.updater.DERIVATIONS["orca-editor"], lambda _, release=release: release)
                def fetcher(_, failure=failure):
                    if failure:
                        raise failure
                    return b"fixture"
                with contextlib.redirect_stderr(output), patch.dict(self.updater.PROFILES, {"orca-editor": profile}), patch.object(self.updater, "prefetch_hash", side_effect=OSError("download failed")):
                    updates = self.updater.collect_updates(["orca-editor"], fetcher=fetcher)
                self.assertIn(expected, output.getvalue())
                self.assertEqual(bool(updates), expected != "Up to date")

    def test_nix_progress_arrives_before_download_exits_and_stdout_stays_json(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            nix = Path(directory) / "nix"
            nix.write_text(f"#!{sys.executable}\nimport sys\nprint('downloading demo.zip', file=sys.stderr, flush=True)\nsys.stdin.readline()\nprint('{{\"hash\": \"sha256-test\"}}')\n")
            nix.chmod(0o755)
            code = f"import runpy; m = runpy.run_path({str(SCRIPT)!r}); print(m['prefetch_hash']('https://example.invalid/demo.zip'))"
            with subprocess.Popen([sys.executable, "-c", code], env={**os.environ, "PATH": directory + os.pathsep + os.environ["PATH"]}, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE) as process:
                try:
                    ready, _, _ = select.select([process.stderr], [], [], 5)
                    self.assertTrue(ready, "Nix progress was hidden while the download was running")
                    self.assertIn(b"downloading demo.zip", os.read(process.stderr.fileno(), 4096))
                    self.assertIsNone(process.poll())
                finally:
                    stdout, stderr = process.communicate(b"continue\n", timeout=5)
                self.assertEqual(process.returncode, 0, stderr)
                self.assertEqual(stdout, b"sha256-test\n")

    def test_progressing_prefetch_has_no_python_total_deadline(self) -> None:
        # Scale any aggregate deadline down so the regression takes milliseconds,
        # not five minutes. The real child continues producing download progress.
        original_run = subprocess.run
        def scaled_run(command, **kwargs):
            if kwargs.get("timeout") is not None:
                kwargs["timeout"] = 0.01
            return original_run(command, **kwargs)
        with tempfile.TemporaryDirectory() as directory:
            nix = Path(directory) / "nix"
            nix.write_text(
                f"#!{sys.executable}\nimport sys, time\n"
                "for i in range(5):\n print('receiving data', file=sys.stderr, flush=True); time.sleep(0.02)\n"
                "print('{\"hash\": \"sha256-complete\"}')\n"
            )
            nix.chmod(0o755)
            with patch.dict(os.environ, {"PATH": directory + os.pathsep + os.environ["PATH"]}), patch.object(self.updater.subprocess, "run", side_effect=scaled_run):
                try:
                    result = self.updater.prefetch_hash("https://example.invalid/large.zip")
                except subprocess.TimeoutExpired:
                    self.fail("Progressing prefetch was killed by an aggregate Python deadline")
            self.assertEqual(result, "sha256-complete")

    def test_failed_report_keeps_json_stdout_and_emits_final_error_summaries(self) -> None:
        updates = [
            {"package": "dia-browser", "status": "error", "reason": "connection stalled"},
            {"package": "orca-editor", "status": "error", "reason": "HTTP 403"},
        ]
        stdout, stderr = io.StringIO(), io.StringIO()
        with tempfile.TemporaryDirectory() as directory:
            report = Path(directory) / "report.json"
            with patch.object(self.updater, "collect_updates", return_value=updates), contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                status = self.updater.main(["--write", "--output", str(report)])
            self.assertEqual(status, 1)
            self.assertEqual(json.loads(stdout.getvalue()), json.loads(report.read_text()))
            self.assertIn("[ERROR] dia-browser: connection stalled", stderr.getvalue())
            self.assertIn("[ERROR] orca-editor: HTTP 403", stderr.getvalue())

    @unittest.skipUnless(shutil.which("nix"), "requires Nix for native transfer contracts")
    def test_native_timeouts_allow_progress_and_reject_stalls(self) -> None:
        payload = b"download-fixture" * 512
        expected = "sha256-" + base64.b64encode(hashlib.sha256(payload).digest()).decode()
        for mode, stall_timeout, succeeds in [("steady", 1, True), ("stalled", 1, False), ("paused", 0, True)]:
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as directory:
                stop = threading.Event()
                class Handler(http.server.BaseHTTPRequestHandler):
                    def log_message(self, *_):
                        pass
                    def do_GET(self):
                        self.send_response(200)
                        self.send_header("Content-Length", str(len(payload)))
                        self.end_headers()
                        try:
                            self.wfile.write(payload[:1024])
                            self.wfile.flush()
                            if mode == "stalled":
                                stop.wait(12)
                                return
                            if mode == "paused":
                                stop.wait(2)
                            for offset in range(1024, len(payload), 1024):
                                if mode == "steady":
                                    stop.wait(0.25)
                                self.wfile.write(payload[offset:offset + 1024])
                                self.wfile.flush()
                        except (BrokenPipeError, ConnectionResetError):
                            pass
                server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
                thread = threading.Thread(target=server.serve_forever, daemon=True)
                thread.start()
                url = f"http://127.0.0.1:{server.server_port}/fixture"
                environment = {
                    **os.environ,
                    "NIX_REMOTE": f"local?root={Path(directory).resolve()}/store-root",
                    "NIX_CONFIG": f"experimental-features = nix-command\nstalled-download-timeout = {stall_timeout}\ndownload-attempts = 1\nconnect-timeout = 2\n",
                }
                try:
                    started = time.monotonic()
                    # Run Nix directly so the fixture watchdog kills and waits
                    # for the downloader itself, not just a Python wrapper.
                    result = subprocess.run(["nix", "store", "prefetch-file", "--json", url], env=environment, capture_output=True, text=True, timeout=15)
                    if succeeds:
                        self.assertEqual(result.returncode, 0, result.stderr)
                        self.assertEqual(json.loads(result.stdout)["hash"], expected)
                        self.assertGreater(time.monotonic() - started, 1)
                    else:
                        self.assertNotEqual(result.returncode, 0)
                        self.assertIn("Timeout", result.stderr)
                finally:
                    stop.set()
                    server.shutdown()
                    server.server_close()
                    thread.join(timeout=2)

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
