from __future__ import annotations

import unittest
from pathlib import Path

from hermes_bootstrap.manifest import load_manifest
from hermes_bootstrap.onepassword import build_onepassword_config


MANIFEST = Path(__file__).parents[2] / "bootstrap-manifest.yaml"


class OnePasswordConfigTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.manifest = load_manifest(MANIFEST)

    def test_default_config_maps_shared_and_default_slack_references(self) -> None:
        config = build_onepassword_config(self.manifest, "default")

        self.assertEqual(config["enabled"], True)
        self.assertEqual(config["account"], "my.1password.com")
        self.assertEqual(config["service_account_token_env"], "OP_SERVICE_ACCOUNT_TOKEN")
        self.assertEqual(config["binary_path"], "/usr/bin/op")
        self.assertEqual(config["override_existing"], True)
        self.assertEqual(
            config["env"],
            {
                "HERMES_DASHBOARD_BASIC_AUTH_USERNAME": (
                    "op://openclaw/Hermes Agent Dashboard/username"
                ),
                "GITHUB_PERSONAL_ACCESS_TOKEN": (
                    "op://openclaw/GitHubUsedOpenClawPAT/credential"
                ),
                "GH_TOKEN": "op://openclaw/GitHubUsedOpenClawPAT/credential",
                "GITHUB_TOKEN": "op://openclaw/GitHubUsedOpenClawPAT/credential",
                "SLACK_BOT_TOKEN": "op://openclaw/SlackBot-OpenClaw/bot_token",
                "SLACK_APP_TOKEN": "op://openclaw/SlackBot-OpenClaw/app_level_token",
                "SLACK_ALLOWED_USERS": "op://openclaw/SlackBot-OpenClaw/SLACK_ALLOWED_USERS",
            },
        )

    def test_named_profile_uses_its_slack_item(self) -> None:
        config = build_onepassword_config(self.manifest, "rick")

        self.assertEqual(
            config["env"]["SLACK_BOT_TOKEN"],
            "op://openclaw/SlackBot-Rick/bot_token",
        )
        self.assertNotIn("API_SERVER_KEY", config["env"])
        self.assertNotIn("HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH", config["env"])
        self.assertNotIn("HERMES_DASHBOARD_BASIC_AUTH_SECRET", config["env"])


if __name__ == "__main__":
    unittest.main()
