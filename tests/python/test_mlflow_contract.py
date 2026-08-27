"""Static contract tests for the local MLflow Compose runtime."""

from __future__ import annotations

import json
import subprocess
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
COMPOSE_FILE = REPOSITORY_ROOT / "docker/mlflow/compose.yml"
ENDPOINTS_FILE = REPOSITORY_ROOT / "docker/mlflow/endpoints.yml"
MLFLOW_IMAGE = (
    "ghcr.io/mlflow/mlflow:v3.12.0@"
    "sha256:2562eea480f1053f4feac2460eeadd9662f2099911254db2f1dc7260613aa2af"
)
MLFLOW_BIND = {
    "type": "bind",
    "source": "${MLFLOW_DATA_DIR:-${USERPROFILE:-${HOME}}/.local/share/mlflow}",
    "target": "/mlflow",
}


class MlflowContractTests(unittest.TestCase):
    @staticmethod
    def _load_yaml(path: Path) -> dict[str, object]:
        result = subprocess.run(
            [
                "ruby",
                "-ryaml",
                "-rjson",
                "-e",
                "puts JSON.generate(YAML.load_file(ARGV.fetch(0)))",
                str(path),
            ],
            check=True,
            capture_output=True,
            text=True,
        )
        return json.loads(result.stdout)

    def setUp(self) -> None:
        self.assertTrue(COMPOSE_FILE.is_file(), f"missing {COMPOSE_FILE}")
        self.assertTrue(ENDPOINTS_FILE.is_file(), f"missing {ENDPOINTS_FILE}")
        self.compose = self._load_yaml(COMPOSE_FILE)
        self.manifest = self._load_yaml(ENDPOINTS_FILE)
        self.mlflow = self.compose["services"]["mlflow"]

    def test_compose_pins_the_released_multi_platform_mlflow_image(self) -> None:
        self.assertEqual(self.mlflow["image"], MLFLOW_IMAGE)
        self.assertNotIn("platform", self.mlflow)

    def test_compose_exposes_only_the_loopback_mlflow_port(self) -> None:
        self.assertEqual(
            self.mlflow["ports"], ["127.0.0.1:${MLFLOW_PORT:-5000}:5000"]
        )

    def test_compose_declares_the_external_local_ai_services_network(self) -> None:
        self.assertEqual(
            self.compose["networks"]["local-ai-services"],
            {"name": "local-ai-services", "external": True},
        )
        self.assertEqual(self.mlflow["networks"], ["local-ai-services"])

    def test_compose_uses_the_persistent_mlflow_store_and_artifacts_mount(self) -> None:
        self.assertEqual(self.mlflow["volumes"], [MLFLOW_BIND])
        self.assertEqual(
            self.mlflow["command"],
            [
                "mlflow",
                "server",
                "--host",
                "0.0.0.0",
                "--port",
                "5000",
                "--backend-store-uri",
                "sqlite:////mlflow/mlflow.db",
                "--default-artifact-root",
                "/mlflow/artifacts",
            ],
        )

    def test_compose_reaches_host_ollama_and_checks_health(self) -> None:
        self.assertEqual(
            self.mlflow["extra_hosts"], ["host.docker.internal:host-gateway"]
        )
        self.assertEqual(
            self.mlflow["healthcheck"],
            {
                "test": [
                    "CMD",
                    "python",
                    "-c",
                    "import urllib.request; urllib.request.urlopen('http://127.0.0.1:5000/health', timeout=5)",
                ],
                "interval": "10s",
                "timeout": "10s",
                "retries": 30,
                "start_period": "20s",
            },
        )
        self.assertNotIn("ollama", self.compose["services"])

    def test_manifest_contains_the_two_non_secret_ollama_endpoints(self) -> None:
        endpoints = self.manifest["endpoints"]
        self.assertEqual(
            endpoints,
            [
                {
                    "name": "ollama-chat-default",
                    "provider": "ollama",
                    "model_name": "qwen3.6:35b",
                    "api_base": "http://host.docker.internal:11434",
                    "capability": "chat",
                    "usage_tracking": True,
                },
                {
                    "name": "ollama-embedding-default",
                    "provider": "ollama",
                    "model_name": "qwen3-embedding:0.6b",
                    "api_base": "http://host.docker.internal:11434",
                    "capability": "embeddings",
                    "usage_tracking": True,
                },
            ],
        )
        self.assertTrue(
            all("secret" not in json.dumps(item).lower() for item in endpoints)
        )


if __name__ == "__main__":
    unittest.main()
