from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


BOOTSTRAP_ROOT = Path(__file__).resolve().parents[3] / "scripts" / "python"
sys.path.insert(0, str(BOOTSTRAP_ROOT))

from hermes_bootstrap.errors import ApplyError
from hermes_bootstrap.google_gmail import install_google_gmail_credentials
from hermes_bootstrap.payload import GoogleCalendarSecret


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

    def test_replace_failure_preserves_credentials_and_rerun_converges(self) -> None:
        target = self.root / "google-gmail-mcp"
        target.mkdir(mode=0o700)
        oauth = target / "gcp-oauth.keys.json"
        oauth.write_text("old-oauth", encoding="utf-8")
        oauth.chmod(0o600)
        credentials = target / "credentials.json"
        credentials.write_text("host-local-tokens", encoding="utf-8")
        credentials.chmod(0o600)

        with patch("hermes_bootstrap.distributions.os.replace", side_effect=OSError):
            with self.assertRaises(ApplyError):
                install_google_gmail_credentials(self.root, self.secret)

        self.assertEqual(oauth.read_text(encoding="utf-8"), "old-oauth")
        self.assertEqual(credentials.read_text(encoding="utf-8"), "host-local-tokens")
        self.assertEqual(
            sorted(path.name for path in target.iterdir()),
            ["credentials.json", "gcp-oauth.keys.json"],
        )

        install_google_gmail_credentials(self.root, self.secret)
        install_google_gmail_credentials(self.root, self.secret)

        self.assertEqual(
            oauth.read_text(encoding="utf-8"), self.secret.oauth_credentials_json
        )
        self.assertEqual(credentials.read_text(encoding="utf-8"), "host-local-tokens")


if __name__ == "__main__":
    unittest.main()
