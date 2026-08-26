"""Dockerfile contracts for the Hermes Hindsight client."""

from __future__ import annotations

import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[4]
DOCKERFILE = REPOSITORY_ROOT / "docker/hermes-agent/Dockerfile"
HINDSIGHT_CLIENT_VERSION = "0.6.1"


class DockerfileContractTests(unittest.TestCase):
    def test_runtime_installs_the_gateway_convergence_command(self) -> None:
        dockerfile = DOCKERFILE.read_text(encoding="utf-8")

        self.assertIn(
            "COPY hermes-agent/gateway_convergence.py /usr/local/bin/hermes-gateway-converge",
            dockerfile,
        )
        self.assertIn("chmod 0755 /usr/local/bin/hermes-gateway-converge", dockerfile)

    def test_runtime_installs_and_verifies_the_supported_hindsight_client(self) -> None:
        dockerfile = DOCKERFILE.read_text(encoding="utf-8")

        self.assertIn(
            f"ARG HINDSIGHT_CLIENT_VERSION={HINDSIGHT_CLIENT_VERSION}", dockerfile
        )
        self.assertIn(
            'uv pip install --python /opt/hermes/.venv/bin/python \\\n'
            '      "hindsight-client==${HINDSIGHT_CLIENT_VERSION}" \\\n'
            '  && /opt/hermes/.venv/bin/python -c \\\n'
            '      "from importlib.metadata import version; assert '
            "version('hindsight-client') == '${HINDSIGHT_CLIENT_VERSION}'\"",
            dockerfile,
        )


if __name__ == "__main__":
    unittest.main()
