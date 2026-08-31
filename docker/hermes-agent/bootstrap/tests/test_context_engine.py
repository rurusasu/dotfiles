from __future__ import annotations

import stat
import sys
import tempfile
import unittest
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path

import yaml

BOOTSTRAP_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BOOTSTRAP_ROOT))

from hermes_bootstrap.errors import ApplyError, ValidationError
from hermes_bootstrap.transaction import Transaction


class RecordingTransaction:
    def __init__(self) -> None:
        self.snapshots: list[Path] = []

    def snapshot(self, path: Path) -> None:
        self.snapshots.append(path)

    @contextmanager
    def bind_reserved_directory(self, path: Path) -> Iterator[int | None]:
        del path
        yield None


class ContextEngineConfigurationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve() / "data"
        self.root.mkdir(mode=0o700)

    def write_target(self, profile: str, content: str | None = None) -> Path:
        target = self.root if profile == "default" else self.root / "profiles" / profile
        target.mkdir(parents=True, exist_ok=True)
        (target / "config.yaml").write_text(
            content
            or (
                "model:\n  name: test\n"
                "memory:\n  provider: hindsight\n  custom_policy: keep\n"
                "plugins:\n"
                "  enabled:\n    - existing-plugin\n    - hermes-lcm\n    - hermes-lcm\n"
                "  disabled:\n    - hermes-lcm\n    - unrelated-plugin\n"
                "unrelated:\n  nested: true\n"
            ),
            encoding="utf-8",
        )
        return target

    def test_reconciles_root_and_all_managed_profiles_without_changing_memory(
        self,
    ) -> None:
        from hermes_bootstrap.context_engine import (
            CONTEXT_ENGINE_NAME,
            CONTEXT_PLUGIN_NAME,
            install_context_engine_configurations,
        )

        profiles = (
            "default",
            "rick",
            "hoffman",
            "risarisa",
            "nancy",
            "kuroda",
            "shiraishi",
        )
        targets = tuple((profile, self.write_target(profile)) for profile in profiles)
        transaction = RecordingTransaction()

        install_context_engine_configurations(targets, transaction)

        for profile, target in targets:
            with self.subTest(profile=profile):
                config = yaml.safe_load(
                    (target / "config.yaml").read_text(encoding="utf-8")
                )
                self.assertEqual(config["context"], {"engine": CONTEXT_ENGINE_NAME})
                self.assertEqual(
                    config["memory"], {"provider": "hindsight", "custom_policy": "keep"}
                )
                self.assertEqual(
                    config["plugins"]["enabled"],
                    ["existing-plugin", CONTEXT_PLUGIN_NAME],
                )
                self.assertEqual(config["plugins"]["disabled"], ["unrelated-plugin"])
                self.assertEqual(config["unrelated"], {"nested": True})
                self.assertEqual(
                    stat.S_IMODE((target / "config.yaml").stat().st_mode), 0o600
                )

        self.assertEqual(len(transaction.snapshots), len(targets))

    def test_reconciliation_is_idempotent(self) -> None:
        from hermes_bootstrap.context_engine import (
            install_context_engine_configurations,
        )

        target = self.write_target("default")
        first = RecordingTransaction()
        install_context_engine_configurations((("default", target),), first)
        expected = (target / "config.yaml").read_bytes()

        second = RecordingTransaction()
        install_context_engine_configurations((("default", target),), second)

        self.assertEqual((target / "config.yaml").read_bytes(), expected)
        self.assertEqual(second.snapshots, [])

    def test_rejects_invalid_plugin_configuration_without_touching_config(self) -> None:
        from hermes_bootstrap.context_engine import (
            install_context_engine_configurations,
        )

        target = self.write_target("default", "plugins:\n  enabled: invalid\n")
        original = (target / "config.yaml").read_bytes()
        transaction = RecordingTransaction()

        with self.assertRaisesRegex(
            ApplyError, "could not reconcile Hermes context engine configuration"
        ):
            install_context_engine_configurations((("default", target),), transaction)

        self.assertEqual((target / "config.yaml").read_bytes(), original)
        self.assertEqual(transaction.snapshots, [])

    def test_validation_requires_engine_activation_and_plugin_enablement(self) -> None:
        from hermes_bootstrap.context_engine import (
            install_context_engine_configurations,
            validate_context_engine_installation,
        )

        target = self.write_target("default")
        transaction = Transaction.begin(self.root)
        install_context_engine_configurations((("default", target),), transaction)
        transaction.commit()
        validate_context_engine_installation((("default", target),))

        config_path = target / "config.yaml"
        config = yaml.safe_load(config_path.read_text(encoding="utf-8"))
        config["context"]["engine"] = "compressor"
        config_path.write_text(
            yaml.safe_dump(config, sort_keys=False), encoding="utf-8"
        )
        config_path.chmod(0o600)

        with self.assertRaisesRegex(
            ValidationError, "installed Hermes context engine configuration is invalid"
        ):
            validate_context_engine_installation((("default", target),))

    def test_distribution_comparison_ignores_only_bootstrap_owned_lcm_entries(self) -> None:
        from hermes_bootstrap.distributions import without_bootstrap_managed_config

        config = {
            "context": {"engine": "lcm", "custom": "keep"},
            "plugins": {
                "enabled": ["hermes-lcm", "other-plugin"],
                "disabled": ["hermes-lcm", "disabled-plugin"],
                "custom": True,
            },
            "unrelated": "keep",
        }

        self.assertEqual(
            without_bootstrap_managed_config(config),
            {
                "context": {"custom": "keep"},
                "plugins": {
                    "enabled": ["other-plugin"],
                    "disabled": ["disabled-plugin"],
                    "custom": True,
                },
                "unrelated": "keep",
            },
        )


if __name__ == "__main__":
    unittest.main()
