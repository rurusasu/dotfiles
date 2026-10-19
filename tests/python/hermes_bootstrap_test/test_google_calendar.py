from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


BOOTSTRAP_ROOT = Path(__file__).resolve().parents[3] / "scripts" / "python"
sys.path.insert(0, str(BOOTSTRAP_ROOT))

from hermes_bootstrap.google_calendar import install_google_calendar_credentials
from hermes_bootstrap.errors import ApplyError
from hermes_bootstrap.payload import GoogleCalendarSecret


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

    def test_replace_failure_preserves_original_credentials_and_rerun_succeeds(self) -> None:
        target = self.root / "google-calendar-mcp"
        target.mkdir(mode=0o700)
        oauth = target / "gcp-oauth.keys.json"
        tokens = target / "tokens.json"
        oauth.write_text("old-oauth", encoding="utf-8")
        tokens.write_text("old-tokens", encoding="utf-8")
        oauth.chmod(0o600)
        tokens.chmod(0o600)
        user_file = target / "keep.json"
        user_file.write_text("unmanaged", encoding="utf-8")

        with (
            mock.patch(
                "hermes_bootstrap.distributions.os.replace",
                side_effect=OSError("replace failed"),
            ),
            self.assertRaises(ApplyError),
        ):
            install_google_calendar_credentials(self.root, self.secret)

        self.assertEqual(oauth.read_text(encoding="utf-8"), "old-oauth")
        self.assertEqual(tokens.read_text(encoding="utf-8"), "old-tokens")
        install_google_calendar_credentials(self.root, self.secret)
        self.assertEqual(oauth.read_text(encoding="utf-8"), self.secret.oauth_credentials_json)
        self.assertEqual(tokens.read_text(encoding="utf-8"), self.secret.tokens_json)
        self.assertEqual(user_file.read_text(encoding="utf-8"), "unmanaged")


if __name__ == "__main__":
    unittest.main()
