"""Container and Compose contracts for the Hermes bootstrap service."""

from __future__ import annotations

import json
import os
import unittest
from pathlib import Path
from typing import Any

import yaml


REPOSITORY_ROOT = Path(__file__).resolve().parents[4]
COMPOSE_FILE = REPOSITORY_ROOT / "docker/hermes-agent/compose.yml"
DOCKERFILE = REPOSITORY_ROOT / "docker/hermes-agent/Dockerfile"
RESOLVED_CONFIG_ENV = "HERMES_BOOTSTRAP_COMPOSE_CONFIG_JSON"
DATA_BIND = {
    "type": "bind",
    "source": "${HERMES_DATA_DIR:-${USERPROFILE:-${HOME}}/.hermes}",
    "target": "/opt/data",
}
XURL_BIND = {
    "type": "bind",
    "source": "${HERMES_DATA_DIR:-${USERPROFILE:-${HOME}}/.hermes/.xurl",
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
        self.hermes = self.services["hermes"]
        self.bootstrap = self.services.get("hermes-bootstrap")

    def test_bootstrap_service_is_an_isolated_hermes_companion(self) -> None:
        self.assertIsNotNone(self.bootstrap)
        assert self.bootstrap is not None
        self.assertEqual(self.bootstrap["build"], self.hermes["build"])
        self.assertEqual(self.bootstrap["image"], self.hermes["image"])
        self.assertEqual(self.bootstrap["volumes"], [DATA_BIND])
        self.assertEqual(self.bootstrap["environment"], {"HERMES_HOME": "/opt/data"})
        self.assertEqual(self.bootstrap["profiles"], ["bootstrap"])
        self.assertEqual(self.bootstrap["entrypoint"], "/usr/local/bin/hermes-bootstrap")
        self.assertEqual(self.bootstrap["command"], "apply")
        for forbidden in ("container_name", "ports", "restart", "depends_on", "networks"):
            self.assertNotIn(forbidden, self.bootstrap)
        self.assertFalse(any(_is_secret_key(key) for key in self.bootstrap["environment"]))

    def test_gateway_uses_the_canonical_shared_lifelog_path(self) -> None:
        self.assertEqual(self.hermes["environment"]["LIFELOG_ROOT"], "/opt/data/shared/lifelog")

    def test_gateway_exposes_the_authenticated_api_on_the_container_interface(self) -> None:
        self.assertEqual(self.hermes["environment"]["API_SERVER_HOST"], "0.0.0.0")
        self.assertIn("127.0.0.1:${HERMES_API_PORT:-8642}:8642", self.hermes["ports"])
        self.assertNotIn("API_SERVER_KEY", self.hermes["environment"])

    def test_browser_mcp_and_novnc_share_the_compose_chromium_process(self) -> None:
        chromium = self.services["chromium"]
        browser_mcp = self.services["browser-mcp"]
        self.assertEqual(
            browser_mcp["depends_on"],
            {"chromium": {"condition": "service_healthy"}},
        )
        self.assertEqual(browser_mcp["networks"], chromium["networks"])
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
                "--host",
                "0.0.0.0",
                "--port",
                "8080",
                "--",
                "node_modules/.bin/chrome-devtools-mcp",
                "--browser-url=http://chromium:9222",
                "--no-usage-statistics",
            ],
        )

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
        self.assertNotIn("ports", xapi)
        self.assertEqual(
            xapi["healthcheck"]["test"],
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
        self.assertEqual(
            self.hermes["depends_on"]["xapi-mcp"],
            {"condition": "service_healthy"},
        )

    def test_dockerfile_builds_runtime_test_and_final_stages(self) -> None:
        dockerfile = DOCKERFILE.read_text(encoding="utf-8")
        pinned_base = (
            "docker.io/nousresearch/hermes-agent@sha256:"
            "dbd5484b4e822307e78bb68d5bf17a57eece7c5e278ca38b8670df9499f14731"
        )

        self.assertIn(f"FROM {pinned_base} AS hermes-bootstrap-runtime", dockerfile)
        self.assertIn("COPY bootstrap/hermes_bootstrap /usr/local/lib/hermes-bootstrap/hermes_bootstrap", dockerfile)
        self.assertIn(
            "COPY bootstrap-manifest.yaml /usr/local/share/hermes-bootstrap/bootstrap-manifest.yaml",
            dockerfile,
        )
        self.assertIn("COPY hermes-bootstrap /usr/local/bin/hermes-bootstrap", dockerfile)
        self.assertIn("chmod 0755 /usr/local/bin/hermes-bootstrap", dockerfile)
        self.assertIn("FROM hermes-bootstrap-runtime AS hermes-bootstrap-test", dockerfile)
        self.assertIn("COPY bootstrap/tests /workspace/docker/hermes-agent/bootstrap/tests", dockerfile)
        self.assertIn("python -m unittest discover", dockerfile)
        self.assertTrue(dockerfile.rstrip().endswith("FROM hermes-bootstrap-runtime\n\nWORKDIR /"))

    def test_host_resolved_contract_matches_the_structural_contract(self) -> None:
        config_path = os.environ.get(RESOLVED_CONFIG_ENV)
        if config_path is None:
            self.skipTest("host-resolved Compose config was not supplied")

        resolved = json.loads(Path(config_path).read_text(encoding="utf-8"))["services"]
        hermes = resolved["hermes"]
        bootstrap = resolved["hermes-bootstrap"]

        self.assertEqual(bootstrap["image"], hermes["image"])
        self.assertEqual(_volume_for_target(bootstrap, "/opt/data"), _volume_for_target(hermes, "/opt/data"))
        self.assertEqual(bootstrap["environment"], {"HERMES_HOME": "/opt/data"})
        self.assertEqual(bootstrap["profiles"], ["bootstrap"])
        self.assertEqual(bootstrap["entrypoint"], ["/usr/local/bin/hermes-bootstrap"])
        self.assertEqual(bootstrap["command"], ["apply"])
        self.assertFalse(bootstrap.get("ports"))
        self.assertFalse(bootstrap.get("depends_on"))
        self.assertFalse(any(_is_secret_key(key) for key in bootstrap["environment"]))


def _volume_for_target(service: dict[str, Any], target: str) -> dict[str, Any]:
    return next(volume for volume in service["volumes"] if volume["target"] == target)


def _is_secret_key(key: str) -> bool:
    return any(token in key.upper() for token in ("SECRET", "TOKEN", "PASSWORD", "API_KEY"))


if __name__ == "__main__":
    unittest.main()
