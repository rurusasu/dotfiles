"""Build contract for the isolated Hermes X MCP image."""

from __future__ import annotations

import unittest
from pathlib import Path


DOCKERFILE = (
    Path(__file__).resolve().parents[2] / "docker" / "hermes-xapi-mcp" / "Dockerfile"
)


class XapiImageContractTests(unittest.TestCase):
    def test_xurl_postinstall_is_enabled_so_the_native_binary_is_installed(self) -> None:
        dockerfile = DOCKERFILE.read_text(encoding="utf-8")

        self.assertIn("npm ci --omit=dev", dockerfile)
        self.assertNotIn("npm ci --omit=dev --ignore-scripts", dockerfile)


if __name__ == "__main__":
    unittest.main()
