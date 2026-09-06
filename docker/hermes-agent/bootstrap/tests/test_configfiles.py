from __future__ import annotations

import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import yaml

from hermes_bootstrap.configfiles import (
    reconcile_onepassword_cli_permissions,
    reconcile_onepassword_configurations,
    reconcile_xapi_configurations,
    validate_xapi_configurations,
)
from hermes_bootstrap.errors import ApplyError
from hermes_bootstrap.manifest import load_manifest
from hermes_bootstrap.transaction import Transaction


MANIFEST = Path(__file__).parents[2] / "bootstrap-manifest.yaml"


class OnePasswordConfigFileTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve() / "data"
        self.root.mkdir(mode=0o700)
        self.manifest = load_manifest(MANIFEST)

    def test_reconciler_preserves_unmanaged_config_and_adds_managed_refs(self) -> None:
        path = self.root / "config.yaml"
        path.write_text(
            "model:\n  name: test\n"
            "secrets:\n"
            "  onepassword:\n"
            "    cache_ttl_seconds: 42\n"
            "    env:\n"
            "      OPENAI_API_KEY: op://Private/OpenAI/credential\n"
            "      SLACK_BOT_TOKEN: op://openclaw/SlackBot/bot_token\n"
            "      SLACK_APP_TOKEN: op://openclaw/SlackBot/app_level_token\n"
            "      SLACK_ALLOWED_USERS: op://openclaw/SlackBot/SLACK_ALLOWED_USERS\n",
            encoding="utf-8",
        )

        tx = Transaction.begin(self.root)
        reconcile_onepassword_configurations(
            self.manifest, (("default", self.root),), tx
        )
        tx.commit()

        config = yaml.safe_load(path.read_text(encoding="utf-8"))
        onepassword = config["secrets"]["onepassword"]
        self.assertEqual(config["model"]["name"], "test")
        self.assertEqual(onepassword["cache_ttl_seconds"], 300)
        self.assertEqual(
            onepassword["env"]["OPENAI_API_KEY"],
            "op://Private/OpenAI/credential",
        )
        self.assertEqual(
            onepassword["env"]["DISCORD_BOT_TOKEN"],
            "op://openclaw/Master/Discord/bot_token",
        )
        self.assertNotIn("SLACK_BOT_TOKEN", onepassword["env"])
        self.assertNotIn("SLACK_APP_TOKEN", onepassword["env"])
        self.assertNotIn("SLACK_ALLOWED_USERS", onepassword["env"])

    def test_reconciler_is_idempotent(self) -> None:
        path = self.root / "config.yaml"
        path.write_text("model:\n  name: test\n", encoding="utf-8")

        first = Transaction.begin(self.root)
        reconcile_onepassword_configurations(
            self.manifest, (("default", self.root),), first
        )
        first.commit()
        expected = path.read_bytes()

        second = Transaction.begin(self.root)
        reconcile_onepassword_configurations(
            self.manifest, (("default", self.root),), second
        )
        second.commit()

        self.assertEqual(path.read_bytes(), expected)

    def test_reconciler_rejects_a_missing_managed_config(self) -> None:
        transaction = Transaction.begin(self.root)
        with self.assertRaisesRegex(ApplyError, "managed Hermes configuration"):
            reconcile_onepassword_configurations(
                self.manifest, (("default", self.root),), transaction
            )
        transaction.rollback()

    def test_xapi_reconciler_repairs_an_existing_preserved_profile(self) -> None:
        profile = self.root / "profiles" / "personal-ops"
        profile.mkdir(parents=True)
        path = profile / "config.yaml"
        path.write_text(
            "model:\n"
            "  name: test\n"
            "mcp_servers:\n"
            "  calendar:\n"
            "    url: http://calendar-mcp:8080/mcp\n",
            encoding="utf-8",
        )

        tx = Transaction.begin(self.root)
        reconcile_xapi_configurations((profile,), tx)
        tx.commit()

        config = yaml.safe_load(path.read_text(encoding="utf-8"))
        self.assertEqual(
            config["mcp_servers"]["xapi"],
            {
                "url": "http://xapi-mcp:8080/mcp",
                "connect_timeout": 300,
            },
        )
        self.assertEqual(
            config["mcp_servers"]["calendar"],
            {"url": "http://calendar-mcp:8080/mcp"},
        )

    def test_xapi_reconciliation_rolls_back_before_an_unsafe_profile(self) -> None:
        first = self.root / "profiles" / "first"
        first.mkdir(parents=True)
        first_config = first / "config.yaml"
        first_config.write_text("model:\n  name: unchanged\n", encoding="utf-8")
        original = first_config.read_bytes()

        second = self.root / "profiles" / "second"
        second.mkdir()
        outside = self.root / "outside.yaml"
        outside.write_text("model: outside\n", encoding="utf-8")
        (second / "config.yaml").symlink_to(outside)

        tx = Transaction.begin(self.root)
        with self.assertRaisesRegex(ApplyError, "X API configuration"):
            reconcile_xapi_configurations((first, second), tx)
        self.assertNotEqual(first_config.read_bytes(), original)
        tx.rollback()

        self.assertEqual(first_config.read_bytes(), original)
        self.assertEqual(outside.read_text(encoding="utf-8"), "model: outside\n")

    def test_xapi_reconciler_and_validator_reject_unsafe_entries(self) -> None:
        operations = (
            ("reconcile", self._reconcile_xapi),
            ("validate", self._validate_xapi),
        )
        for operation_name, operation in operations:
            for scenario in ("symlink", "directory", "fifo", "hardlink"):
                with (
                    self.subTest(operation=operation_name, scenario=scenario),
                    tempfile.TemporaryDirectory() as temp,
                ):
                    root = Path(temp).resolve() / "data"
                    profile = root / "profiles" / "personal-ops"
                    profile.mkdir(parents=True)
                    config = profile / "config.yaml"
                    outside = root / "outside.yaml"
                    outside.write_text("model: outside\n", encoding="utf-8")
                    if scenario == "symlink":
                        config.symlink_to(outside)
                    elif scenario == "directory":
                        config.mkdir()
                    elif scenario == "fifo":
                        os.mkfifo(config)
                    else:
                        os.link(outside, config)

                    operation(root, profile)
                    self.assertEqual(
                        outside.read_text(encoding="utf-8"),
                        "model: outside\n",
                    )

    def test_xapi_reconciler_and_validator_reject_unreadable_entries(self) -> None:
        operations = (
            ("reconcile", self._reconcile_xapi),
            ("validate", self._validate_xapi),
        )
        for operation_name, operation in operations:
            with (
                self.subTest(operation=operation_name),
                tempfile.TemporaryDirectory() as temp,
            ):
                root = Path(temp).resolve() / "data"
                profile = root / "profiles" / "personal-ops"
                profile.mkdir(parents=True)
                config = profile / "config.yaml"
                config.write_text("model: local\n", encoding="utf-8")
                original_read_text = Path.read_text

                def read_text(path: Path, *args: object, **kwargs: object) -> str:
                    if path == config:
                        raise PermissionError("denied")
                    return original_read_text(path, *args, **kwargs)

                with mock.patch.object(
                    Path,
                    "read_text",
                    autospec=True,
                    side_effect=read_text,
                ):
                    operation(root, profile)

    def _reconcile_xapi(self, root: Path, profile: Path) -> None:
        tx = Transaction.begin(root)
        try:
            with self.assertRaisesRegex(ApplyError, "X API configuration"):
                reconcile_xapi_configurations((profile,), tx)
        finally:
            tx.rollback()

    def _validate_xapi(self, root: Path, profile: Path) -> None:
        del root
        with self.assertRaisesRegex(ApplyError, "X API configuration"):
            validate_xapi_configurations((profile,))

    def test_cli_config_directory_is_private_and_idempotent(self) -> None:
        op_directory = self.root / ".config" / "op"
        op_directory.mkdir(parents=True, mode=0o755)
        op_directory.chmod(0o755)
        config = op_directory / "config"
        config.write_text("account state\n", encoding="utf-8")
        config.chmod(0o600)

        first = Transaction.begin(self.root)
        reconcile_onepassword_cli_permissions(self.root, first)
        first.commit()

        self.assertEqual(op_directory.stat().st_mode & 0o777, 0o700)
        self.assertEqual(config.read_text(encoding="utf-8"), "account state\n")
        self.assertEqual(config.stat().st_mode & 0o777, 0o600)

        second = Transaction.begin(self.root)
        reconcile_onepassword_cli_permissions(self.root, second)
        second.commit()

        self.assertEqual(op_directory.stat().st_mode & 0o777, 0o700)

    def test_cli_config_permission_rolls_back_with_the_bootstrap(self) -> None:
        op_directory = self.root / ".config" / "op"
        op_directory.mkdir(parents=True, mode=0o755)
        op_directory.chmod(0o755)

        tx = Transaction.begin(self.root)
        reconcile_onepassword_cli_permissions(self.root, tx)
        self.assertEqual(op_directory.stat().st_mode & 0o777, 0o700)
        tx.rollback()

        self.assertEqual(op_directory.stat().st_mode & 0o777, 0o755)

    def test_cli_config_permission_rejects_a_symlink(self) -> None:
        outside = self.root / "outside"
        outside.mkdir(mode=0o755)
        config_parent = self.root / ".config"
        config_parent.mkdir(mode=0o700)
        (config_parent / "op").symlink_to(outside, target_is_directory=True)

        tx = Transaction.begin(self.root)
        with self.assertRaisesRegex(Exception, "1Password CLI configuration"):
            reconcile_onepassword_cli_permissions(self.root, tx)
        tx.rollback()

        self.assertEqual(outside.stat().st_mode & 0o777, 0o755)


if __name__ == "__main__":
    unittest.main()
