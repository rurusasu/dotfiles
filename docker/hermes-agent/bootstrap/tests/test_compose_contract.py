"""Container and Compose contracts for the Hermes bootstrap service."""

from __future__ import annotations

import json
import os
import unittest
from pathlib import Path
from typing import Any

import yaml


REPOSITORY_ROOT = Path(__file__).resolve().parents[4]
COMPOSE_FILE = REPOSITORY_ROOT / "docker/hermes-service/compose.yml"
HINDSIGHT_COMPOSE_FILE = REPOSITORY_ROOT / "docker/local-ai-services/compose.yml"
HINDSIGHT_ENV_FILE = REPOSITORY_ROOT / "docker/hindsight/hindsight.env"
HINDSIGHT_SHELL_SCRIPT = REPOSITORY_ROOT / "scripts/sh/hindsight.sh"
HINDSIGHT_POWERSHELL_SCRIPT = REPOSITORY_ROOT / "scripts/powershell/hindsight.ps1"
DOCKERFILE = REPOSITORY_ROOT / "docker/hermes-agent/Dockerfile"
RESOLVED_CONFIG_ENV = "HERMES_BOOTSTRAP_COMPOSE_CONFIG_JSON"
DATA_BIND = {
    "type": "bind",
    "source": "${HERMES_DATA_DIR:-${USERPROFILE:-${HOME}}/.hermes}",
    "target": "/opt/data",
}
XURL_BIND = {
    "type": "bind",
    "source": "${HERMES_DATA_DIR:-${USERPROFILE:-${HOME}}/.hermes}/.xurl",
    "target": "/root/.xurl",
}
HINDSIGHT_IMAGE = (
    "ghcr.io/vectorize-io/hindsight:0.9.1@"
    "sha256:a0e937366261b8a8f20ebcaf13758c689c381dcbbf01684e4375c2787c8c666d"
)
HINDSIGHT_ENVIRONMENT = {
    "HINDSIGHT_API_LLM_PROVIDER": "ollama",
    "HINDSIGHT_API_LLM_BASE_URL": "http://mlflow:5000/gateway/mlflow/v1",
    "HINDSIGHT_API_LLM_MODEL": "ollama-chat-default",
    "HINDSIGHT_API_LLM_REASONING_EFFORT": "none",
    "HINDSIGHT_API_LLM_OLLAMA_NUM_CTX": "32768",
    "HINDSIGHT_API_LLM_STRICT_SCHEMA": "true",
    "HINDSIGHT_API_LLM_STRICT_SCHEMA_RETAIN": "true",
    "HINDSIGHT_API_LLM_STRICT_SCHEMA_REFLECT": "true",
    "HINDSIGHT_API_LLM_STRICT_SCHEMA_CONSOLIDATION": "true",
    "HINDSIGHT_API_LLM_MAX_CONCURRENT": "1",
    "HINDSIGHT_API_LLM_TIMEOUT": "300",
    "HINDSIGHT_API_FAIL_ON_EXTRACTION_ERRORS": "true",
    "HINDSIGHT_API_RETAIN_WALL_TIMEOUT": "300",
    "HINDSIGHT_API_ENABLE_DRY_RUN_EXTRACT": "true",
    "HINDSIGHT_API_EMBEDDINGS_PROVIDER": "openai",
    "HINDSIGHT_API_EMBEDDINGS_OPENAI_BASE_URL": "http://mlflow:5000/gateway/openai/v1",
    "HINDSIGHT_API_EMBEDDINGS_OPENAI_API_KEY": "ollama",
    "HINDSIGHT_API_EMBEDDINGS_OPENAI_MODEL": "ollama-embedding-default",
    "HINDSIGHT_OLLAMA_LLM_MODEL": "qwen3.6:35b",
    "HINDSIGHT_OLLAMA_EMBEDDING_MODEL": "qwen3-embedding:0.6b",
    "HINDSIGHT_API_RERANKER_PROVIDER": "local",
    "HINDSIGHT_API_RERANKER_LOCAL_MODEL": "BAAI/bge-reranker-v2-m3",
    "HINDSIGHT_API_RERANKER_LOCAL_FORCE_CPU": "true",
    "HINDSIGHT_API_ENABLE_RERANKING": "true",
}
HINDSIGHT_PG_BIND = {
    "type": "bind",
    "source": "${HINDSIGHT_DATA_DIR:-${USERPROFILE:-${HOME}}/.local/share/hindsight}/pg0",
    "target": "/home/hindsight/.pg0",
}
HINDSIGHT_CACHE_BIND = {
    "type": "bind",
    "source": "${HINDSIGHT_DATA_DIR:-${USERPROFILE:-${HOME}}/.local/share/hindsight}/cache",
    "target": "/home/hindsight/.cache",
}
HINDSIGHT_HEALTHCHECK = (
    "python -c \"import json,urllib.request; d=json.load(urllib.request.urlopen("
    "'http://127.0.0.1:8888/health', timeout=5)); raise SystemExit(0 if "
    "d.get('status') == 'healthy' and d.get('database') == 'connected' else 1)\""
)
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
        self.hindsight_compose = yaml.safe_load(
            HINDSIGHT_COMPOSE_FILE.read_text(encoding="utf-8")
        )
        self.hindsight_services = self.hindsight_compose["services"]

    def test_bootstrap_service_is_an_isolated_hermes_companion(self) -> None:
        self.assertIsNotNone(self.bootstrap)
        assert self.bootstrap is not None
        self.assertEqual(self.bootstrap["build"], self.hermes["build"])
        self.assertEqual(
            self.hermes["build"],
            {"context": "..", "dockerfile": "hermes-agent/Dockerfile"},
        )
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

    def test_gateway_uses_the_canonical_hermes_home(self) -> None:
        self.assertEqual(self.hermes["environment"]["HERMES_HOME"], "/opt/data")

    def test_gateway_reconnects_on_the_first_failed_discord_liveness_sample(self) -> None:
        self.assertEqual(
            self.hermes["environment"]["HERMES_DISCORD_LIVENESS_FAILURE_THRESHOLD"],
            "${HERMES_DISCORD_LIVENESS_FAILURE_THRESHOLD:-1}",
        )

    def test_hindsight_is_a_pinned_multi_arch_private_memory_runtime(self) -> None:
        self.assertNotIn("hindsight", self.services)
        hindsight = self.hindsight_services.get("hindsight")
        self.assertIsNotNone(hindsight)
        assert hindsight is not None

        self.assertEqual(hindsight["image"], HINDSIGHT_IMAGE)
        self.assertNotIn("platform", hindsight)
        self.assertEqual(hindsight["container_name"], "local-ai-services-hindsight")
        self.assertEqual(hindsight["restart"], "unless-stopped")
        self.assertEqual(
            hindsight["env_file"], [{"path": "../hindsight/hindsight.env", "required": True}],
        )
        self.assertNotIn("extra_hosts", hindsight)
        self.assertEqual(
            hindsight["ports"],
            [
                "127.0.0.1:${HINDSIGHT_API_PORT:-8888}:8888",
                "127.0.0.1:${HINDSIGHT_UI_PORT:-9999}:9999",
            ],
        )
        self.assertFalse(any("5432" in port for port in hindsight["ports"]))
        self.assertEqual(
            hindsight["volumes"], [HINDSIGHT_PG_BIND, HINDSIGHT_CACHE_BIND],
        )
        self.assertEqual(hindsight["shm_size"], "1g")
        self.assertEqual(
            hindsight["networks"],
            {"local-ai-services": {"aliases": ["hindsight"]}},
        )

        mlflow = self.hindsight_services.get("mlflow")
        self.assertIsNotNone(mlflow)
        assert mlflow is not None
        self.assertEqual(mlflow["container_name"], "local-ai-services-mlflow")
        self.assertEqual(mlflow["networks"], ["local-ai-services"])

    def test_hindsight_readiness_requires_a_healthy_connected_database(self) -> None:
        hindsight = self.hindsight_services.get("hindsight")
        self.assertIsNotNone(hindsight)
        assert hindsight is not None

        self.assertEqual(
            hindsight["healthcheck"],
            {
                "test": ["CMD-SHELL", HINDSIGHT_HEALTHCHECK],
                "interval": "10s",
                "timeout": "10s",
                "retries": 30,
                "start_period": "60s",
            },
        )

    def test_hermes_can_reach_memory_without_waiting_for_its_runtime(self) -> None:
        self.assertEqual(self.hermes["networks"], ["hermes-browser", "local-ai-services"])
        self.assertEqual(
            self.hermes["extra_hosts"], ["host.docker.internal:host-gateway"]
        )
        self.assertNotIn("hindsight", self.hermes["depends_on"])
        self.assertEqual(
            self.hindsight_compose["networks"]["local-ai-services"],
            {"name": "local-ai-services", "external": True},
        )
        self.assertNotIn("dotfiles-memory", str(self.compose))
        self.assertNotIn("dotfiles-memory", str(self.hindsight_compose))

    def test_hindsight_environment_is_the_exact_non_secret_model_runtime_contract(self) -> None:
        environment = {}
        for line in HINDSIGHT_ENV_FILE.read_text(encoding="utf-8").splitlines():
            if line:
                key, value = line.split("=", 1)
                environment[key] = value

        self.assertEqual(environment, HINDSIGHT_ENVIRONMENT)

    def test_hindsight_preparation_uses_native_ollama_models(self) -> None:
        if not HINDSIGHT_SHELL_SCRIPT.is_file() or not HINDSIGHT_POWERSHELL_SCRIPT.is_file():
            self.skipTest("Hindsight preparation scripts are outside the bootstrap test context")
        shell_source = HINDSIGHT_SHELL_SCRIPT.read_text(encoding="utf-8")
        powershell_source = HINDSIGHT_POWERSHELL_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("HINDSIGHT_OLLAMA_LLM_MODEL", shell_source)
        self.assertIn("HINDSIGHT_OLLAMA_EMBEDDING_MODEL", shell_source)
        self.assertNotIn(
            'hindsight_env_value "$compose_file" HINDSIGHT_API_LLM_MODEL', shell_source
        )
        self.assertNotIn(
            'hindsight_env_value "$compose_file" HINDSIGHT_API_EMBEDDINGS_OPENAI_MODEL',
            shell_source,
        )
        self.assertIn("HINDSIGHT_OLLAMA_LLM_MODEL", powershell_source)
        self.assertIn("HINDSIGHT_OLLAMA_EMBEDDING_MODEL", powershell_source)
        self.assertNotIn("HINDSIGHT_API_LLM_MODEL", powershell_source)
        self.assertNotIn("HINDSIGHT_API_EMBEDDINGS_OPENAI_MODEL", powershell_source)

    def test_hermes_services_load_the_private_service_account_environment_file(self) -> None:
        expected = [
            {
                "path": "${HERMES_DATA_DIR:-${USERPROFILE:-${HOME}}/.hermes}/.op.env",
                "required": False,
            }
        ]
        self.assertEqual(self.hermes["env_file"], expected)
        self.assertEqual(self.bootstrap["env_file"], expected)

    def test_gateway_exposes_the_authenticated_api_on_the_container_interface(self) -> None:
        self.assertEqual(self.hermes["environment"]["API_SERVER_HOST"], "0.0.0.0")
        self.assertIn("127.0.0.1:${HERMES_API_PORT:-8642}:8642", self.hermes["ports"])
        self.assertNotIn("API_SERVER_KEY", self.hermes["environment"])

    def test_browser_mcp_and_novnc_share_the_compose_chromium_process(self) -> None:
        chromium = self.services["chromium"]
        browser_mcp = self.services["browser-mcp"]
        self.assertNotIn("platform", chromium)
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
        self.assertNotIn("ports", xapi)
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
        self.assertEqual(
            self.hermes["depends_on"]["xapi-mcp"],
            {"condition": "service_healthy"},
        )

    def test_dockerfile_builds_runtime_test_and_final_stages(self) -> None:
        dockerfile = DOCKERFILE.read_text(encoding="utf-8")
        latest_base = "docker.io/nousresearch/hermes-agent:latest"

        self.assertIn(f"FROM {latest_base} AS hermes-bootstrap-runtime", dockerfile)
        self.assertIn("COPY hermes-agent/bootstrap/hermes_bootstrap /usr/local/lib/hermes-bootstrap/hermes_bootstrap", dockerfile)
        self.assertIn(
            "COPY hermes-agent/bootstrap-manifest.yaml /usr/local/share/hermes-bootstrap/bootstrap-manifest.yaml",
            dockerfile,
        )
        self.assertIn(
            "COPY hermes-agent/hermes-bootstrap /usr/local/bin/hermes-bootstrap",
            dockerfile,
        )
        self.assertIn("chmod 0755 /usr/local/bin/hermes-bootstrap", dockerfile)
        self.assertIn("FROM hermes-bootstrap-runtime AS hermes-bootstrap-test", dockerfile)
        self.assertIn("COPY hermes-agent/bootstrap/tests /workspace/docker/hermes-agent/bootstrap/tests", dockerfile)
        self.assertIn("python -m unittest discover", dockerfile)
        self.assertTrue(dockerfile.rstrip().endswith("FROM hermes-bootstrap-runtime\n\nWORKDIR /"))

    def test_runtime_image_installs_the_official_onepassword_cli(self) -> None:
        dockerfile = DOCKERFILE.read_text(encoding="utf-8")

        self.assertIn(
            "https://downloads.1password.com/linux/keys/1password.asc",
            dockerfile,
        )
        self.assertIn(
            "https://downloads.1password.com/linux/debian/%s stable main",
            dockerfile,
        )
        self.assertIn("apt-get install -y --no-install-recommends 1password-cli", dockerfile)
        self.assertIn("op --version", dockerfile)

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
