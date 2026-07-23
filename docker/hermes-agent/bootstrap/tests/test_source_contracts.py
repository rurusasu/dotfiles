from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path


BOOTSTRAP_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BOOTSTRAP_ROOT))

from hermes_bootstrap.errors import ValidationError
from hermes_bootstrap.git import StagedSource
from hermes_bootstrap.models import DistributionSource
from hermes_bootstrap.source_contracts import validate_chrome_mcp_sources


VALID_CONFIG = """\
model:
  provider: openai-codex
mcp_servers:
  chrome:
    url: http://browser-mcp:8080/mcp
    connect_timeout: 120
  retained:
    url: https://example.invalid/mcp
"""


class SourceContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def staged(self, name: str, config: str | None) -> StagedSource:
        path = self.root / name
        path.mkdir()
        if config is not None:
            (path / "config.yaml").write_text(config, encoding="utf-8")
        declaration = DistributionSource(
            name=name,
            source=f"https://github.com/example/{name}.git",
            ref="main",
            target=(
                Path("/opt/data")
                if name == "default"
                else Path("/opt/data/profiles") / name
            ),
            manifest_name=(
                "root-distribution.yaml"
                if name == "default"
                else "distribution.yaml"
            ),
        )
        return StagedSource(declaration=declaration, path=path, commit="a" * 40)

    def test_accepts_root_and_profiles_while_preserving_other_servers(self) -> None:
        staged = (
            self.staged("default", VALID_CONFIG),
            self.staged("rick", VALID_CONFIG),
        )

        validate_chrome_mcp_sources(staged)

    def test_rejects_every_noncanonical_shape_without_exposing_values(self) -> None:
        invalid = {
            "missing-file": None,
            "malformed-yaml": "mcp_servers: [\n",
            "duplicate-key": """\
mcp_servers:
  chrome:
    url: http://browser-mcp:8080/mcp
    url: https://secret.invalid/mcp
    connect_timeout: 120
""",
            "top-level-sequence": "- mcp_servers\n",
            "mcp-sequence": "mcp_servers: []\n",
            "missing-chrome": "mcp_servers: {}\n",
            "chrome-sequence": "mcp_servers:\n  chrome: []\n",
            "wrong-url": """\
mcp_servers:
  chrome:
    url: https://secret.invalid/mcp
    connect_timeout: 120
""",
            "missing-timeout": """\
mcp_servers:
  chrome:
    url: http://browser-mcp:8080/mcp
""",
            "string-timeout": """\
mcp_servers:
  chrome:
    url: http://browser-mcp:8080/mcp
    connect_timeout: "120"
""",
            "boolean-timeout": """\
mcp_servers:
  chrome:
    url: http://browser-mcp:8080/mcp
    connect_timeout: true
""",
            "wrong-timeout": """\
mcp_servers:
  chrome:
    url: http://browser-mcp:8080/mcp
    connect_timeout: 60
""",
            "extra-chrome-key": """\
mcp_servers:
  chrome:
    url: http://browser-mcp:8080/mcp
    connect_timeout: 120
    token: secret-marker
""",
        }
        for case, config in invalid.items():
            with self.subTest(case=case):
                staged = self.staged(case, config)
                with self.assertRaises(ValidationError) as caught:
                    validate_chrome_mcp_sources((staged,))
                message = str(caught.exception)
                self.assertIn(case, message)
                self.assertIn("config.yaml", message)
                self.assertNotIn("secret-marker", message)
                self.assertNotIn("secret.invalid", message)
                self.assertIsNone(caught.exception.__cause__)

    def test_manifest_additions_are_covered_without_a_profile_allowlist(self) -> None:
        stages = (
            self.staged("default", VALID_CONFIG),
            self.staged("rick", VALID_CONFIG),
            self.staged("future-profile", "mcp_servers: {}\n"),
        )

        with self.assertRaisesRegex(ValidationError, "future-profile.*config.yaml"):
            validate_chrome_mcp_sources(stages)


if __name__ == "__main__":
    unittest.main()
