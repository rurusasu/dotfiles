"""Dockerfile contracts for the Hermes runtime integrations."""

from __future__ import annotations

import unittest
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[4]
DOCKERFILE = REPOSITORY_ROOT / "docker/hermes-agent/Dockerfile"
BOOTSTRAP_WRAPPER = REPOSITORY_ROOT / "docker/hermes-agent/hermes-bootstrap"
HINDSIGHT_CLIENT_VERSION = "0.6.1"
HINDSIGHT_PLUGIN_COMMIT = "dc75038866a3966b5bf5c82ff57c7a758bb4070a"
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

    def test_runtime_installs_the_storage_ownership_command_without_changing_final_user(self) -> None:
        dockerfile = DOCKERFILE.read_text(encoding="utf-8")

        self.assertIn(
            "COPY hermes-agent/hermes_storage_ownership.py /usr/local/bin/hermes-storage-ownership",
            dockerfile,
        )
        self.assertIn("chmod 0755 /usr/local/bin/hermes-storage-ownership", dockerfile)
        self.assertIn("test_hermes_storage_ownership.py", dockerfile)
        final_stage = dockerfile.rsplit("FROM hermes-bootstrap-runtime", 1)[1]
        self.assertNotIn("USER 10000", final_stage)

    def test_bootstrap_wrapper_rejects_the_wrong_identity_and_sets_a_private_umask(self) -> None:
        wrapper = BOOTSTRAP_WRAPPER.read_text(encoding="utf-8")

        self.assertIn('"$(id -u)" = 10000', wrapper)
        self.assertIn('"$(id -g)" = 10000', wrapper)
        self.assertIn("umask 077", wrapper)

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

    def test_runtime_installs_the_pinned_catalog_hindsight_provider_and_loads_it_for_real(self) -> None:
        dockerfile = DOCKERFILE.read_text(encoding="utf-8").replace("\\\n", " ")

        self.assertIn(
            "COPY hermes-agent/hindsight_acceptance.py /usr/local/bin/hindsight_acceptance.py",
            dockerfile,
        )
        normalize_command = "sed -i 's/\\r$//' /usr/local/bin/hindsight_acceptance.py"
        symlink_command = (
            "ln -s /usr/local/bin/hindsight_acceptance.py "
            "/usr/local/bin/hermes-hindsight-acceptance"
        )
        help_command = "/usr/local/bin/hermes-hindsight-acceptance --help >/dev/null"
        self.assertIn(normalize_command, dockerfile)
        self.assertIn("chmod 0755 /usr/local/bin/hindsight_acceptance.py", dockerfile)
        self.assertIn(symlink_command, dockerfile)
        self.assertIn(help_command, dockerfile)
        self.assertLess(
            dockerfile.index(normalize_command), dockerfile.index(symlink_command)
        )
        self.assertLess(
            dockerfile.index(symlink_command), dockerfile.index(help_command)
        )
        self.assertIn(
            f"ARG HINDSIGHT_PLUGIN_COMMIT={HINDSIGHT_PLUGIN_COMMIT}", dockerfile
        )
        self.assertIn("https://github.com/vectorize-io/hindsight", dockerfile)
        self.assertIn(
            'git -C /tmp/hindsight-provider fetch --quiet --depth 1 origin "${HINDSIGHT_PLUGIN_COMMIT}"',
            dockerfile,
        )
        self.assertIn(
            'test "$(git -C /tmp/hindsight-provider rev-parse FETCH_HEAD)" = "${HINDSIGHT_PLUGIN_COMMIT}"',
            dockerfile,
        )
        self.assertIn(
            "git -C /tmp/hindsight-provider archive FETCH_HEAD hindsight-integrations/hermes",
            dockerfile,
        )
        self.assertIn(
            "tar -x --strip-components=2 -C /opt/hermes/plugins/memory/hindsight",
            dockerfile,
        )
        self.assertIn(
            'from hindsight_acceptance import _resolved_provider', dockerfile
        )
        self.assertIn(
            'provider_factory=None,',
            dockerfile,
            "the image build must exercise the production factory, not a fake provider",
        )
        self.assertIn(
            'provider.name == "hindsight"',
            dockerfile,
        )
        self.assertIn(
            'provider.__class__.__module__ == "plugins.memory.hindsight"',
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
