from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

import yaml


BOOTSTRAP_ROOT = Path(__file__).resolve().parents[3] / "scripts" / "python"
sys.path.insert(0, str(BOOTSTRAP_ROOT))

from hermes_bootstrap.google_calendar import (
    install_google_calendar_configurations,
    install_google_calendar_credentials,
    validate_google_calendar_installation,
)
from hermes_bootstrap.errors import ValidationError
from hermes_bootstrap.payload import GoogleCalendarSecret
from hermes_bootstrap.transaction import Transaction


class GoogleCalendarCredentialTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve() / "data"
        self.root.mkdir(mode=0o700)
        self.secret = GoogleCalendarSecret(
            oauth_credentials_json='{"installed":{"client_id":"id","client_secret":"secret"}}',
            tokens_json='{"accounts":{"shared":{"refresh_token":"refresh"}}}',
        )

    def install_valid_layout(self) -> tuple[Path, ...]:
        targets = (self.root, self.root / "profiles" / "nancy")
        for target in targets:
            target.mkdir(parents=True, exist_ok=True)
            (target / "config.yaml").write_text(
                "mcp_servers:\n"
                "  chrome:\n"
                "    url: http://127.0.0.1:8765/mcp\n",
                encoding="utf-8",
            )
        tx = Transaction.begin(self.root)
        install_google_calendar_configurations(targets, tx)
        install_google_calendar_credentials(self.root, self.secret, tx)
        tx.commit()
        return targets

    def test_installs_shared_credentials_with_private_permissions(self) -> None:
        tx = Transaction.begin(self.root)

        install_google_calendar_credentials(self.root, self.secret, tx)
        tx.commit()

        target = self.root / "google-calendar-mcp"
        self.assertEqual(target.stat().st_mode & 0o777, 0o700)
        self.assertEqual(
            (target / "gcp-oauth.keys.json").read_text(encoding="utf-8"),
            self.secret.oauth_credentials_json,
        )
        self.assertEqual(
            (target / "tokens.json").read_text(encoding="utf-8"),
            self.secret.tokens_json,
        )
        self.assertEqual(
            (target / "gcp-oauth.keys.json").stat().st_mode & 0o777,
            0o600,
        )
        self.assertEqual((target / "tokens.json").stat().st_mode & 0o777, 0o600)

    def test_rollback_restores_previous_credentials(self) -> None:
        target = self.root / "google-calendar-mcp"
        target.mkdir(mode=0o700)
        oauth = target / "gcp-oauth.keys.json"
        tokens = target / "tokens.json"
        oauth.write_text("old-oauth", encoding="utf-8")
        tokens.write_text("old-tokens", encoding="utf-8")
        oauth.chmod(0o600)
        tokens.chmod(0o600)
        tx = Transaction.begin(self.root)

        install_google_calendar_credentials(self.root, self.secret, tx)
        tx.rollback()

        self.assertEqual(oauth.read_text(encoding="utf-8"), "old-oauth")
        self.assertEqual(tokens.read_text(encoding="utf-8"), "old-tokens")

    def test_identical_credentials_are_not_rewritten(self) -> None:
        first = Transaction.begin(self.root)
        install_google_calendar_credentials(self.root, self.secret, first)
        first.commit()
        target = self.root / "google-calendar-mcp"
        before = {path.name: path.stat().st_ino for path in target.iterdir()}
        second = Transaction.begin(self.root)

        install_google_calendar_credentials(self.root, self.secret, second)
        second.commit()

        self.assertEqual(
            {path.name: path.stat().st_ino for path in target.iterdir()},
            before,
        )

    def test_installs_the_same_mcp_configuration_for_all_profiles(self) -> None:
        targets = (self.root, self.root / "profiles" / "nancy")
        for target in targets:
            target.mkdir(parents=True, exist_ok=True)
            (target / "config.yaml").write_text(
                "mcp_servers:\n"
                "  chrome:\n"
                "    url: http://browser-mcp:8080/mcp\n",
                encoding="utf-8",
            )
        tx = Transaction.begin(self.root)

        install_google_calendar_configurations(targets, tx)
        tx.commit()

        for target in targets:
            installed = yaml.safe_load((target / "config.yaml").read_text(encoding="utf-8"))
            self.assertEqual(
                installed["mcp_servers"]["calendar"],
                {
                    "command": "npx",
                    "args": ["--yes", "--package", "@cocal/google-calendar-mcp@2.6.2", "google-calendar-mcp"],
                    "connect_timeout": 300,
                    "env": {
                        "GOOGLE_OAUTH_CREDENTIALS": str(self.root / "google-calendar-mcp/gcp-oauth.keys.json"),
                        "GOOGLE_CALENDAR_MCP_TOKEN_PATH": str(self.root / "google-calendar-mcp/tokens.json"),
                    },
                },
            )

    def test_calendar_installation_preserves_an_existing_gmail_server(self) -> None:
        gmail = (
            "  gmail:\n"
            "    url: https://gmailmcp.googleapis.com/mcp/v1\n"
            "    auth: oauth\n"
            "    connect_timeout: 315\n"
        )
        target = self.root
        target.mkdir(parents=True, exist_ok=True)
        (target / "config.yaml").write_text(
            "mcp_servers:\n"
            "  retained:\n"
            "    url: https://example.invalid/mcp\n"
            + gmail,
            encoding="utf-8",
        )
        tx = Transaction.begin(self.root)

        install_google_calendar_configurations((target,), tx)
        tx.commit()

        installed = (target / "config.yaml").read_text(encoding="utf-8")
        self.assertIn(gmail, installed)
        self.assertIn("retained:\n    url: https://example.invalid/mcp", installed)

    def test_validation_accepts_every_calendar_configuration_and_shared_credentials(
        self,
    ) -> None:
        targets = self.install_valid_layout()

        validate_google_calendar_installation(self.root, targets)

    def test_validation_rejects_each_missing_calendar_configuration(self) -> None:
        targets = self.install_valid_layout()

        for target in targets:
            config = target / "config.yaml"
            original = config.read_text(encoding="utf-8")
            with self.subTest(target=target):
                config.write_text("mcp_servers: {}\n", encoding="utf-8")
                with self.assertRaisesRegex(
                    ValidationError,
                    "installed Google Calendar configuration is invalid",
                ):
                    validate_google_calendar_installation(self.root, targets)
                config.write_text(original, encoding="utf-8")

    def test_validation_rejects_malformed_symlinked_or_public_credentials(
        self,
    ) -> None:
        targets = self.install_valid_layout()
        credentials = self.root / "google-calendar-mcp"

        for name in ("gcp-oauth.keys.json", "tokens.json"):
            path = credentials / name
            original = path.read_text(encoding="utf-8")
            with self.subTest(name=name, case="missing"):
                path.unlink()
                with self.assertRaises(ValidationError):
                    validate_google_calendar_installation(self.root, targets)
                path.write_text(original, encoding="utf-8")
                path.chmod(0o600)
            with self.subTest(name=name, case="malformed"):
                path.write_text("{}", encoding="utf-8")
                with self.assertRaises(ValidationError):
                    validate_google_calendar_installation(self.root, targets)
                path.write_text(original, encoding="utf-8")
                path.chmod(0o600)
            with self.subTest(name=name, case="symlink"):
                path.unlink()
                path.symlink_to(self.root / "outside-secret")
                with self.assertRaises(ValidationError):
                    validate_google_calendar_installation(self.root, targets)
                path.unlink()
                path.write_text(original, encoding="utf-8")
                path.chmod(0o600)
            with self.subTest(name=name, case="mode"):
                path.chmod(0o644)
                with self.assertRaises(ValidationError):
                    validate_google_calendar_installation(self.root, targets)
                path.chmod(0o600)


if __name__ == "__main__":
    unittest.main()
