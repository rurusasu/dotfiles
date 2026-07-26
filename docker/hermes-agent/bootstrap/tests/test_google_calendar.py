from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path


BOOTSTRAP_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BOOTSTRAP_ROOT))

from hermes_bootstrap.google_calendar import (
    install_google_calendar_configurations,
    install_google_calendar_credentials,
)
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

        expected = (
            "calendar:\n"
            "    command: google-calendar-mcp\n"
            "    connect_timeout: 300\n"
            "    env:\n"
            "      GOOGLE_OAUTH_CREDENTIALS: /opt/data/google-calendar-mcp/gcp-oauth.keys.json\n"
            "      GOOGLE_CALENDAR_MCP_TOKEN_PATH: /opt/data/google-calendar-mcp/tokens.json\n"
        )
        for target in targets:
            self.assertIn(
                expected,
                (target / "config.yaml").read_text(encoding="utf-8"),
            )


if __name__ == "__main__":
    unittest.main()
