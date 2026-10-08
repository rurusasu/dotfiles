"""Compose contracts for the native Hermes browser and X MCP sidecars."""

from __future__ import annotations

import json
import os
import unittest
from pathlib import Path

import yaml


REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
COMPOSE_FILE = REPOSITORY_ROOT / "docker/hermes-service/compose.yml"
RESOLVED_CONFIG_ENV = "HERMES_BOOTSTRAP_COMPOSE_CONFIG_JSON"
XURL_BIND = {
    "type": "bind",
    "source": "${HERMES_DATA_DIR:-${USERPROFILE:-${HOME}}/.hermes}/.xurl",
    "target": "/root/.xurl",
}

EXPECTED_TCP_HEALTHCHECK = (
    "node -e \"const net=require('node:net');const s=net.connect("
    "{host:'127.0.0.1',port:8080},()=>{s.end();process.exit(0)});"
    "s.on('error',()=>process.exit(1));setTimeout(()=>process.exit(1),3000);\""
)

class ComposeContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.compose = yaml.safe_load(COMPOSE_FILE.read_text(encoding="utf-8"))
        self.services = self.compose["services"]

    def test_nix_managed_gateway_is_not_a_compose_service(self) -> None:
        self.assertNotIn("hermes", self.services)
        self.assertNotIn("hermes-bootstrap", self.services)
        self.assertIn("chromium", self.services)
        self.assertIn("browser-mcp", self.services)
        self.assertIn("xapi-mcp", self.services)

    def test_hermes_support_services_keep_their_compose_networks(self) -> None:
        self.assertEqual(self.services["xapi-mcp"]["networks"], ["hermes-browser"])
        self.assertEqual(self.services["browser-mcp"]["networks"], ["hermes-browser"])
        self.assertNotIn("dotfiles-memory", str(self.compose))

    def test_browser_mcp_and_novnc_share_the_compose_chromium_process(self) -> None:
        chromium = self.services["chromium"]
        browser_mcp = self.services["browser-mcp"]
        self.assertNotIn("platform", chromium)
        self.assertEqual(
            browser_mcp["depends_on"],
            {"chromium": {"condition": "service_healthy"}},
        )
        self.assertEqual(browser_mcp["networks"], chromium["networks"])
        self.assertEqual(browser_mcp["ports"], ["127.0.0.1:8765:8080"])
        self.assertIn(
            "127.0.0.1:${HERMES_BROWSER_VIEW_PORT:-6080}:6080",
            chromium["ports"],
        )
        self.assertEqual(
            browser_mcp["command"],
            [
                "node_modules/.bin/mcp-proxy",
                "--server",
                "stream",
                "--requestTimeout",
                "120000",
                "--host",
                "0.0.0.0",
                "--port",
                "8080",
                "--",
                "node_modules/.bin/chrome-devtools-mcp",
                "--browser-url=http://chromium:9222",
                "--experimentalPageIdRouting",
                "--no-usage-statistics",
            ],
        )

    def test_browser_mcp_routes_page_operations_and_bounds_stuck_requests(self) -> None:
        command = self.services["browser-mcp"]["command"]

        self.assertIn("--experimentalPageIdRouting", command)
        self.assertEqual(
            command[
                command.index("--requestTimeout") + 1
            ],
            "120000",
        )

    def test_chrome_entrypoint_does_not_disable_gpu_rendering(self) -> None:
        entrypoint_path = REPOSITORY_ROOT / "docker/hermes-browser/entrypoint.sh"
        if not entrypoint_path.is_file():
            self.skipTest("hermes-browser source is outside the bootstrap test context")

        self.assertNotIn(
            "--disable-gpu", entrypoint_path.read_text(encoding="utf-8")
        )

    def test_browser_image_selects_a_native_browser_for_each_supported_architecture(self) -> None:
        dockerfile_path = REPOSITORY_ROOT / "docker/hermes-browser/Dockerfile"
        entrypoint_path = REPOSITORY_ROOT / "docker/hermes-browser/entrypoint.sh"
        if not dockerfile_path.is_file() or not entrypoint_path.is_file():
            self.skipTest("hermes-browser source is outside the bootstrap test context")

        dockerfile = dockerfile_path.read_text(encoding="utf-8")
        entrypoint = entrypoint_path.read_text(encoding="utf-8")

        self.assertIn("ARG TARGETARCH", dockerfile)
        self.assertIn('amd64)', dockerfile)
        self.assertIn('arm64)', dockerfile)
        self.assertIn("apt-get install -y --no-install-recommends chromium", dockerfile)
        self.assertIn("command -v /usr/bin/google-chrome-stable", entrypoint)
        self.assertIn("command -v /usr/bin/chromium", entrypoint)

    def test_xapi_mcp_is_an_internal_shared_service(self) -> None:
        xapi = self.services.get("xapi-mcp")
        self.assertIsNotNone(xapi)
        assert xapi is not None

        self.assertEqual(
            xapi["build"],
            {"context": "../hermes-xapi-mcp", "dockerfile": "Dockerfile"},
        )
        self.assertEqual(xapi["image"], "local/hermes-xapi-mcp:latest")
        self.assertEqual(xapi["container_name"], "hermes-xapi-mcp")
        self.assertEqual(xapi["networks"], ["hermes-browser"])
        self.assertEqual(xapi["volumes"], [XURL_BIND])
        self.assertEqual(
            xapi["environment"],
            {
                "X_API_CLIENT_ID": "${X_API_CLIENT_ID:-}",
                "X_API_CLIENT_SECRET": "${X_API_CLIENT_SECRET:-}",
            },
        )
        self.assertEqual(xapi["ports"], ["127.0.0.1:8766:8080"])
        self.assertEqual(
            [xapi["healthcheck"]["test"][0], xapi["healthcheck"]["test"][1].strip()],
            ["CMD-SHELL", EXPECTED_TCP_HEALTHCHECK],
        )
        self.assertEqual(
            xapi["command"],
            [
                "node_modules/.bin/mcp-proxy",
                "--server",
                "stream",
                "--host",
                "0.0.0.0",
                "--port",
                "8080",
                "--",
                "/usr/local/bin/hermes-xapi-mcp",
            ],
        )

    def test_host_resolved_contract_matches_the_structural_contract(self) -> None:
        config_path = os.environ.get(RESOLVED_CONFIG_ENV)
        if config_path is None:
            self.skipTest("host-resolved Compose config was not supplied")

        resolved = json.loads(Path(config_path).read_text(encoding="utf-8"))["services"]
        self.assertNotIn("hermes", resolved)
        self.assertNotIn("hermes-bootstrap", resolved)


if __name__ == "__main__":
    unittest.main()
