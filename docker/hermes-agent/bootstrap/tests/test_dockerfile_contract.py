"""Dockerfile contracts for the Hermes runtime integrations."""

from __future__ import annotations

import unittest
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[4]
DOCKERFILE = REPOSITORY_ROOT / "docker/hermes-agent/Dockerfile"
HINDSIGHT_CLIENT_VERSION = "0.6.1"
HERMES_LCM_VERSION = "v0.20.0"
HERMES_LCM_COMMIT = "49e99a272d2d461e5c90732e7ef2bc20e96f0826"


class DockerfileContractTests(unittest.TestCase):
    def test_runtime_tracks_latest_upstream_without_a_digest_pin(self) -> None:
        dockerfile = DOCKERFILE.read_text(encoding="utf-8")

        self.assertTrue(
            dockerfile.startswith(
                "FROM docker.io/nousresearch/hermes-agent:latest "
                "AS hermes-bootstrap-runtime\n"
            )
        )
        self.assertNotIn("hermes-agent:latest@sha256:", dockerfile)
        self.assertIn("from hermes_bootstrap.upstream_patch import (", dockerfile)
        self.assertIn(
            'replace_pattern_variant_once(\n'
            '    Path("/opt/hermes/toolsets.py"),\n'
            "    BROWSER_TOOLSET_VARIANTS,\n"
            ")",
            dockerfile,
        )

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
            "uv pip install --python /opt/hermes/.venv/bin/python \\\n"
            '      "hindsight-client==${HINDSIGHT_CLIENT_VERSION}" \\\n'
            "  && /opt/hermes/.venv/bin/python -c \\\n"
            '      "from importlib.metadata import version; assert '
            "version('hindsight-client') == '${HINDSIGHT_CLIENT_VERSION}'\"",
            dockerfile,
        )

    def test_runtime_bakes_and_verifies_the_pinned_lcm_plugin(self) -> None:
        dockerfile = DOCKERFILE.read_text(encoding="utf-8")

        self.assertIn(f"ARG HERMES_LCM_VERSION={HERMES_LCM_VERSION}", dockerfile)
        self.assertIn(f"ARG HERMES_LCM_COMMIT={HERMES_LCM_COMMIT}", dockerfile)
        self.assertIn(
            "https://github.com/stephenschoettler/hermes-lcm",
            dockerfile,
        )
        self.assertIn(
            'git -C /opt/hermes/plugins/hermes-lcm rev-parse HEAD)" = "${HERMES_LCM_COMMIT}"',
            dockerfile,
        )
        self.assertIn(
            "/opt/hermes/plugins/hermes-lcm/__init__.py",
            dockerfile,
        )
        self.assertIn(
            'engine is not None and engine.name == "lcm"',
            dockerfile,
        )


if __name__ == "__main__":
    unittest.main()
