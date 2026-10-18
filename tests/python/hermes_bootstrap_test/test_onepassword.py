from __future__ import annotations

import os
import subprocess
import unittest
from dataclasses import replace
from pathlib import Path
from unittest import mock

from hermes_bootstrap import onepassword
from hermes_bootstrap.errors import CredentialError
from hermes_bootstrap.manifest import load_manifest
from hermes_bootstrap.models import (
    OnePasswordField,
    OnePasswordItem,
)


MANIFEST = Path(__file__).resolve().parents[3] / "nix/modules/ai_agents/hermes/manifest.yaml"


class OnePasswordConfigTests(unittest.TestCase):
    def setUp(self) -> None:
        self.manifest = load_manifest(MANIFEST)

    def test_github_token_uses_the_declared_reference_and_process_auth(self) -> None:
        item = OnePasswordItem(
            key="github",
            account="example.1password.com",
            vault="test-vault",
            item="GitHub API",
            fields=(
                OnePasswordField("credential", ("token",), reference_name="API/token"),
            ),
        )
        manifest = replace(self.manifest, onepassword_items=(item,))
        supplied_environment = {
            "DOTFILES_HERMES_OP_EXECUTABLE": "/nix/store/test-op/bin/op",
            "OP_SERVICE_ACCOUNT_TOKEN": "service-account-marker",
        }
        with (
            mock.patch.dict(os.environ, {"OP_CONFIG_DIR": "/fixture/op"}),
            mock.patch(
                "subprocess.run",
                return_value=subprocess.CompletedProcess(
                    [], 0, "github-token-marker\n", ""
                ),
            ) as run,
        ):
            token = onepassword.read_github_token(manifest, supplied_environment)

        self.assertEqual(token, "github-token-marker")
        arguments = run.call_args.args[0]
        self.assertEqual(
            arguments,
            [
                "/nix/store/test-op/bin/op", "read", "--account",
                "example.1password.com", "--", "op://test-vault/GitHub API/API/token",
            ],
        )
        self.assertNotIn(token, arguments)
        self.assertNotIn("service-account-marker", arguments)
        self.assertEqual(run.call_args.kwargs["env"]["OP_CONFIG_DIR"], "/fixture/op")
        self.assertEqual(
            run.call_args.kwargs["env"]["OP_SERVICE_ACCOUNT_TOKEN"],
            "service-account-marker",
        )
        self.assertLessEqual(run.call_args.kwargs["timeout"], 30)
        self.assertIs(run.call_args.kwargs["stdin"], subprocess.DEVNULL)

    def test_github_token_failures_hide_cli_output(self) -> None:
        item = OnePasswordItem(
            key="github", account="example.1password.com", vault="test-vault",
            item="GitHub API", fields=(OnePasswordField("credential", ("token",)),),
        )
        manifest = replace(self.manifest, onepassword_items=(item,))
        marker = "private-cli-output-marker"
        with (
            mock.patch(
                "subprocess.run",
                return_value=subprocess.CompletedProcess([], 1, marker, marker),
            ),
            self.assertRaises(CredentialError) as raised,
        ):
            onepassword.read_github_token(manifest, {})

        self.assertEqual(str(raised.exception), "GitHub credentials are unavailable")
        self.assertNotIn(marker, str(raised.exception))


if __name__ == "__main__":
    unittest.main()
