from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import yaml

from hermes_bootstrap.configfiles import (
    reconcile_onepassword_configurations,
    reconcile_xapi_configurations,
    validate_xapi_configurations,
)
from hermes_bootstrap.errors import ApplyError
from hermes_bootstrap.manifest import load_manifest


MANIFEST = Path(__file__).resolve().parents[3] / "nix/modules/ai_agents/hermes/manifest.yaml"


class OnePasswordConfigFileTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve() / "data"
        self.root.mkdir(mode=0o700)
        self.manifest = load_manifest(MANIFEST)

    def test_reconciler_preserves_unmanaged_config_and_secret_references(self) -> None:
        path = self.root / "config.yaml"
        path.write_text(
            "model:\n  name: test\n"
            "platforms:\n"
            "  telegram:\n    enabled: false\n"
            "  discord:\n    allowed_channels: [test-channel]\n"
            "    extra:\n      allow_bots: false\n      custom_rule: retained\n"
            "secrets:\n"
            "  onepassword:\n"
            "    env:\n"
            "      OPENAI_API_KEY: op://Private/OpenAI/credential\n",
            encoding="utf-8",
        )

        reconcile_onepassword_configurations(self.manifest, (("default", self.root),))

        config = yaml.safe_load(path.read_text(encoding="utf-8"))
        onepassword = config["secrets"]["onepassword"]
        self.assertEqual(config["model"]["name"], "test")
        self.assertEqual(config["platforms"]["telegram"], {"enabled": False})
        self.assertEqual(
            config["platforms"]["discord"],
            {
                "allowed_channels": ["test-channel"],
                "allow_bots": "mentions",
                "extra": {"custom_rule": "retained"},
            },
        )
        self.assertEqual(
            onepassword["env"]["OPENAI_API_KEY"],
            "op://Private/OpenAI/credential",
        )

    def test_xapi_reconciliation_can_retry_after_an_unsafe_profile(self) -> None:
        first = self.root / "profiles" / "first"
        first.mkdir(parents=True)
        first_config = first / "config.yaml"
        first_config.write_text("model:\n  name: unchanged\n", encoding="utf-8")
        original = first_config.read_bytes()

        second = self.root / "profiles" / "second"
        second.mkdir()
        outside = self.root / "outside.yaml"
        outside.write_text("model: outside\n", encoding="utf-8")
        second_config = second / "config.yaml"
        second_config.symlink_to(outside)

        with self.assertRaisesRegex(ApplyError, "X API configuration"):
            reconcile_xapi_configurations((first, second))
        self.assertNotEqual(first_config.read_bytes(), original)
        self.assertEqual(outside.read_text(encoding="utf-8"), "model: outside\n")

        installed = first_config.read_bytes()
        second_config.unlink()
        second_config.write_text("model:\n  name: second\n", encoding="utf-8")
        reconcile_xapi_configurations((first, second))

        self.assertEqual(first_config.read_bytes(), installed)
        validate_xapi_configurations((first, second))


if __name__ == "__main__":
    unittest.main()
