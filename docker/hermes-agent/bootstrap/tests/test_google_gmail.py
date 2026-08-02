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
    install_google_gmail_credentials,
    validate_google_gmail_installation,
)
from hermes_bootstrap.payload import GoogleCalendarSecret
from hermes_bootstrap.transaction import Transaction


EXPECTED_GMAIL = {
    "command": "gmail-mcp",
    "connect_timeout": 300,
    "env": {
        "GMAIL_OAUTH_PATH": "/opt/data/google-gmail-mcp/gcp-oauth.keys.json",
        "GMAIL_CREDENTIALS_PATH": "/opt/data/google-gmail-mcp/credentials.json",
    },
    "tools": {
        "include": [
            "search_emails",
            "read_email",
            "get_thread",
            "list_inbox_threads",
            "get_inbox_with_threads",
            "list_email_labels",
            "draft_email",
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
        self.secret = GoogleCalendarSecret(
            oauth_credentials_json=(
                '{"installed":{"client_id":"id","client_secret":"secret"}}'
            ),
            tokens_json='{"refresh_token":"calendar-refresh"}',
        )

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
        install_google_gmail_credentials(self.root, self.secret, tx)
        tx.commit()
        return targets

    def test_installs_shared_credentials_with_private_permissions(self) -> None:
        tx = Transaction.begin(self.root)

        install_google_gmail_credentials(self.root, self.secret, tx)
        tx.commit()

        target = self.root / "google-gmail-mcp"
        self.assertEqual(target.stat().st_mode & 0o777, 0o700)
        self.assertEqual(
            (target / "gcp-oauth.keys.json").read_text(encoding="utf-8"),
            self.secret.oauth_credentials_json,
        )
        self.assertEqual(
            (target / "gcp-oauth.keys.json").stat().st_mode & 0o777,
            0o600,
        )
        self.assertFalse((target / "credentials.json").exists())

    def test_rollback_restores_previous_credentials(self) -> None:
        target = self.root / "google-gmail-mcp"
        target.mkdir(mode=0o700)
        oauth = target / "gcp-oauth.keys.json"
        oauth.write_text("old-oauth", encoding="utf-8")
        oauth.chmod(0o600)
        tx = Transaction.begin(self.root)

        install_google_gmail_credentials(self.root, self.secret, tx)
        tx.rollback()

        self.assertEqual(oauth.read_text(encoding="utf-8"), "old-oauth")

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
            for case in ("missing", "altered"):
                with self.subTest(target=target, case=case):
                    config = yaml.safe_load(original)
                    if case == "missing":
                        del config["mcp_servers"]["gmail"]
                    else:
                        config["mcp_servers"]["gmail"]["url"] = (
                            "https://gmailmcp.googleapis.com/mcp/altered"
                        )
                    config_path.write_text(
                        yaml.safe_dump(config, sort_keys=False), encoding="utf-8"
                    )
                    with self.assertRaisesRegex(
                        ValidationError,
                        "installed Google Gmail configuration is invalid",
                    ):
                        validate_google_gmail_installation(self.root, targets)
                    config_path.write_text(original, encoding="utf-8")

    def test_validation_rejects_malformed_or_public_credentials(self) -> None:
        targets = self.install_valid_layout()
        credentials = self.root / "google-gmail-mcp" / "credentials.json"
        original = (
            '{"tokens":{"refresh_token":"refresh"},'
            '"scopes":["gmail.readonly","gmail.compose"]}'
        )
        credentials.write_text(original, encoding="utf-8")
        credentials.chmod(0o600)

        for case in ("missing-compose-scope", "missing-refresh-token", "public"):
            with self.subTest(case=case):
                if case == "missing-compose-scope":
                    credentials.write_text(
                        '{"tokens":{"refresh_token":"refresh"},'
                        '"scopes":["gmail.readonly"]}',
                        encoding="utf-8",
                    )
                elif case == "missing-refresh-token":
                    credentials.write_text(
                        '{"tokens":{"access_token":"access"},'
                        '"scopes":["gmail.readonly","gmail.compose"]}',
                        encoding="utf-8",
                    )
                else:
                    credentials.chmod(0o644)
                with self.assertRaisesRegex(
                    ValidationError,
                    "installed Google Gmail configuration is invalid",
                ):
                    validate_google_gmail_installation(self.root, targets)
                credentials.write_text(original, encoding="utf-8")
                credentials.chmod(0o600)


if __name__ == "__main__":
    unittest.main()
