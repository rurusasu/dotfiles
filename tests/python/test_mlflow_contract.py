"""Static contract tests for the local MLflow Compose runtime."""

from __future__ import annotations

import json
import subprocess
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
COMPOSE_FILE = REPOSITORY_ROOT / "docker/mlflow/compose.yml"
ENDPOINTS_FILE = REPOSITORY_ROOT / "docker/mlflow/endpoints.yml"
ROOT_TASKFILE = REPOSITORY_ROOT / "Taskfile.yml"
MLFLOW_TASKFILE = REPOSITORY_ROOT / "taskfiles/mlflow/taskfile.yml"
MLFLOW_IMAGE = (
    "ghcr.io/mlflow/mlflow:v3.12.0@"
    "sha256:2562eea480f1053f4feac2460eeadd9662f2099911254db2f1dc7260613aa2af"
)
MLFLOW_BIND = {
    "type": "bind",
    "source": "${MLFLOW_DATA_DIR:-${USERPROFILE:-${HOME}}/.local/share/mlflow}",
    "target": "/mlflow",
}
CONTROL_PLANE_BINDS = [
    {
        "type": "bind",
        "source": "./configure.py",
        "target": "/opt/mlflow/configure.py",
        "read_only": True,
    },
    {
        "type": "bind",
        "source": "./verify.py",
        "target": "/opt/mlflow/verify.py",
        "read_only": True,
    },
    {
        "type": "bind",
        "source": "./endpoints.yml",
        "target": "/opt/mlflow/endpoints.yml",
        "read_only": True,
    },
]


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

    def test_compose_separates_persistent_data_from_read_only_control_plane(self) -> None:
        self.assertEqual(self.mlflow["volumes"], [MLFLOW_BIND, *CONTROL_PLANE_BINDS])
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

    def test_root_taskfile_includes_the_flattened_mlflow_operator_tasks(self) -> None:
        root_taskfile = self._load_yaml(ROOT_TASKFILE)

        self.assertEqual(
            root_taskfile["vars"]["MLFLOW_COMPOSE_FILE"],
            "docker/mlflow/compose.yml",
        )
        self.assertEqual(
            root_taskfile["includes"]["mlflow"],
            {"taskfile": "./taskfiles/mlflow/taskfile.yml", "flatten": True},
        )

    def test_mlflow_operator_tasks_preserve_the_compose_lifecycle_contract(self) -> None:
        self.assertTrue(MLFLOW_TASKFILE.is_file(), f"missing {MLFLOW_TASKFILE}")
        taskfile = self._load_yaml(MLFLOW_TASKFILE)
        tasks = taskfile["tasks"]

        self.assertEqual(
            set(tasks),
            {
                "mlflow:up",
                "mlflow:configure",
                "mlflow:down",
                "mlflow:status",
                "mlflow:logs",
                "mlflow:verify",
            },
        )
        self.assertEqual(taskfile["vars"]["MLFLOW_COMPOSE_FILE"], "docker/mlflow/compose.yml")

        up = tasks["mlflow:up"]
        self.assertTrue(
            any(condition["sh"] == "docker info" for condition in up["preconditions"])
        )
        self.assertEqual(
            up["cmds"],
            [
                {
                    "cmd": "docker network inspect local-ai-services >/dev/null 2>&1 || docker network create local-ai-services",
                    "platforms": ["linux", "darwin"],
                },
                {
                    "cmd": "pwsh -NoProfile -Command \"docker network inspect local-ai-services *> $null; if ($LASTEXITCODE -ne 0) { docker network create local-ai-services }\"",
                    "platforms": ["windows"],
                },
                "docker compose -f {{.MLFLOW_COMPOSE_FILE}} up -d --wait mlflow",
                {"task": "mlflow:configure"},
            ],
        )

        configure = tasks["mlflow:configure"]
        self.assertTrue(
            any(
                "http://127.0.0.1:5000/health" in condition["sh"]
                for condition in configure["preconditions"]
            )
        )
        self.assertEqual(
            configure["cmds"],
            [
                "docker compose -f {{.MLFLOW_COMPOSE_FILE}} exec -T mlflow python /opt/mlflow/configure.py --base-url http://127.0.0.1:5000 --manifest /opt/mlflow/endpoints.yml"
            ],
        )

        self.assertEqual(
            tasks["mlflow:down"]["cmds"],
            ["docker compose -f {{.MLFLOW_COMPOSE_FILE}} stop mlflow"],
        )
        self.assertNotIn("down", " ".join(tasks["mlflow:down"]["cmds"]))
        self.assertNotIn("volume", " ".join(tasks["mlflow:down"]["cmds"]))
        self.assertNotIn("network", " ".join(tasks["mlflow:down"]["cmds"]))
        self.assertTrue(tasks["mlflow:logs"]["interactive"])
        self.assertEqual(
            tasks["mlflow:status"]["cmds"],
            [
                "docker compose -f {{.MLFLOW_COMPOSE_FILE}} ps mlflow",
                {
                    "cmd": "awk '/^[[:space:]]*-[[:space:]]+name:/{print $3}' docker/mlflow/endpoints.yml",
                    "platforms": ["linux", "darwin"],
                },
                {
                    "cmd": "pwsh -NoProfile -Command \"Get-Content docker/mlflow/endpoints.yml | Select-String '^\\s*-\\s+name:\\s*(\\S+)\\s*$' | ForEach-Object { $_.Matches[0].Groups[1].Value }\"",
                    "platforms": ["windows"],
                },
            ],
        )
        self.assertEqual(
            tasks["mlflow:verify"]["cmds"],
            ["docker compose -f {{.MLFLOW_COMPOSE_FILE}} exec -T mlflow python /opt/mlflow/verify.py"],
        )

    def test_hindsight_up_waits_for_mlflow_startup(self) -> None:
        hindsight_taskfile = self._load_yaml(
            REPOSITORY_ROOT / "taskfiles/hindsight/taskfile.yml"
        )

        self.assertIn(
            {"task": "mlflow:up"},
            hindsight_taskfile["tasks"]["hindsight:up"]["deps"],
        )


if __name__ == "__main__":
    unittest.main()
