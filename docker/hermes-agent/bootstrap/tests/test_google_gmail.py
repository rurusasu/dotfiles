from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

import yaml


BOOTSTRAP_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BOOTSTRAP_ROOT))

from hermes_bootstrap.errors import ValidationError
from hermes_bootstrap.google_gmail import (
    install_google_gmail_configurations,
    validate_google_gmail_installation,
)
from hermes_bootstrap.transaction import Transaction


EXPECTED_GMAIL = {
    "url": "https://gmailmcp.googleapis.com/mcp/v1",
    "auth": "oauth",
    "connect_timeout": 315,
    "oauth": {
        "client_id": "${GMAIL_MCP_CLIENT_ID}",
        "client_secret": "${GMAIL_MCP_CLIENT_SECRET}",
        "scope": (
            "https://www.googleapis.com/auth/gmail.readonly "
            "https://www.googleapis.com/auth/gmail.compose"
        ),
    },
    "tools": {
        "include": [
            "search_threads",
            "get_thread",
            "get_message",
            "list_labels",
            "list_drafts",
            "create_draft",
        ],
        "resources": False,
        "prompts": False,
    },
}


class GoogleGmailConfigurationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve() / "data"
        self.root.mkdir(mode=0o700)

    def targets_with_unrelated_servers(self) -> tuple[Path, ...]:
        targets = (self.root, self.root / "profiles" / "nancy")
        for target in targets:
            target.mkdir(parents=True, exist_ok=True)
            (target / "config.yaml").write_text(
                "model:\n  name: test\n"
                "mcp_servers:\n"
                "  chrome:\n"
                "    url: http://browser-mcp:8080/mcp\n"
                "  retained:\n"
                "    url: https://example.invalid/mcp\n",
                encoding="utf-8",
            )
        return targets

    def install_valid_layout(self) -> tuple[Path, ...]:
        targets = self.targets_with_unrelated_servers()
        tx = Transaction.begin(self.root)
        install_google_gmail_configurations(targets, tx)
        tx.commit()
        return targets

    def test_inserts_the_same_gmail_configuration_for_every_target(self) -> None:
        targets = self.targets_with_unrelated_servers()
        tx = Transaction.begin(self.root)

        install_google_gmail_configurations(targets, tx)
        tx.commit()

        for target in targets:
            config = yaml.safe_load((target / "config.yaml").read_text(encoding="utf-8"))
            self.assertEqual(config["mcp_servers"]["gmail"], EXPECTED_GMAIL)
            self.assertEqual(
                config["mcp_servers"]["chrome"],
                {"url": "http://browser-mcp:8080/mcp"},
            )
            self.assertEqual(
                config["mcp_servers"]["retained"],
                {"url": "https://example.invalid/mcp"},
            )

    def test_validation_accepts_every_gmail_configuration(self) -> None:
        targets = self.install_valid_layout()

        validate_google_gmail_installation(self.root, targets)

    def test_validation_rejects_a_missing_or_altered_gmail_entry(self) -> None:
        targets = self.install_valid_layout()

        for target in targets:
            config_path = target / "config.yaml"
            original = config_path.read_text(encoding="utf-8")
            with self.subTest(target=target, case="missing"):
                config = yaml.safe_load(original)
                del config["mcp_servers"]["gmail"]
                config_path.write_text(yaml.safe_dump(config, sort_keys=False), encoding="utf-8")
                with self.assertRaisesRegex(
                    ValidationError,
                    "installed Google Gmail configuration is invalid",
                ):
                    validate_google_gmail_installation(self.root, targets)
            config_path.write_text(original, encoding="utf-8")

    def test_validation_rejects_missing_scope_and_forbidden_tool(self) -> None:
        targets = self.install_valid_layout()
        config_path = targets[0] / "config.yaml"
        original = config_path.read_text(encoding="utf-8")

        for case in ("missing-scope", "forbidden-tool"):
            with self.subTest(case=case):
                config = yaml.safe_load(original)
                gmail = config["mcp_servers"]["gmail"]
                if case == "missing-scope":
                    gmail["oauth"]["scope"] = "https://www.googleapis.com/auth/gmail.readonly"
                else:
                    gmail["tools"]["include"].append("send_message")
                config_path.write_text(yaml.safe_dump(config, sort_keys=False), encoding="utf-8")
                with self.assertRaisesRegex(
                    ValidationError,
                    "installed Google Gmail configuration is invalid",
                ):
                    validate_google_gmail_installation(self.root, targets)
                config_path.write_text(original, encoding="utf-8")


if __name__ == "__main__":
    unittest.main()
