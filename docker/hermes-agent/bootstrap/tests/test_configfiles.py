from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import yaml

from hermes_bootstrap.configfiles import reconcile_onepassword_configurations
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
            "      OPENAI_API_KEY: op://Private/OpenAI/credential\n",
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


if __name__ == "__main__":
    unittest.main()
