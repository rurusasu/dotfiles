from __future__ import annotations

import importlib
import json
import os
import stat
import sys
import tempfile
import unittest
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path
from types import ModuleType
from unittest import mock

import yaml


BOOTSTRAP_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BOOTSTRAP_ROOT))

from hermes_bootstrap.errors import ApplyError, ValidationError
from hermes_bootstrap.transaction import Transaction


EXPECTED_MISSION = (
    "Retain durable preferences, decisions, corrections, entities, relationships, "
    "and temporal facts. Never extract credentials, tokens, private keys, "
    "authentication material, or transient logs as memories."
)
EXPECTED_HINDSIGHT = {
    "mode": "local_external",
    "api_url": "http://hindsight:8888",
    "bank_id": "hermes",
    "bank_id_template": "hermes-{profile}",
    "bank_retain_mission": EXPECTED_MISSION,
    "memory_mode": "hybrid",
    "auto_recall": True,
    "recall_sync": False,
    "recall_types": "observation",
    "recall_budget": "mid",
    "auto_retain": True,
    "retain_async": True,
    "retain_every_n_turns": 1,
    "retain_source": "hermes",
}


def hindsight_module() -> ModuleType:
    try:
        return importlib.import_module("hermes_bootstrap.hindsight")
    except ModuleNotFoundError:
        raise AssertionError("hermes_bootstrap.hindsight is not implemented") from None


class RecordingTransaction:
    def __init__(self) -> None:
        self.snapshots: list[Path] = []
        self.reservations: list[Path] = []

    def snapshot(self, path: Path) -> None:
        self.snapshots.append(path)

    @contextmanager
    def bind_reserved_directory(
        self,
        path: Path,
    ) -> Iterator[int | None]:
        del path
        yield None

    def reserve_directory(self, path: Path, *, remove_tree: bool = True) -> bool:
        del remove_tree
        self.reservations.append(path)
        path.mkdir(mode=0o700)
        return True


class HindsightConfigurationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve() / "data"
        self.root.mkdir(mode=0o700)

    def write_target(
        self,
        profile: str,
        *,
        config: str = (
            "model:\n  name: test\n"
            "memory:\n"
            "  provider: legacy\n"
            "  custom_policy: keep\n"
            "unrelated:\n  nested: true\n"
        ),
    ) -> tuple[str, Path]:
        target = self.root if profile == "default" else self.root / "profiles" / profile
        target.mkdir(parents=True, exist_ok=True)
        path = target / "config.yaml"
        path.write_text(config, encoding="utf-8")
        path.chmod(0o640)
        return profile, target

    def install(self, targets: tuple[tuple[str, Path], ...]) -> None:
        module = hindsight_module()
        tx = Transaction.begin(self.root)
        module.install_hindsight_configurations(targets, tx)
        tx.commit()

    def test_builds_the_exact_approved_non_secret_configuration(self) -> None:
        module = hindsight_module()

        self.assertEqual(module.HINDSIGHT_RETAIN_MISSION, EXPECTED_MISSION)
        self.assertEqual(module.build_hindsight_config(), EXPECTED_HINDSIGHT)

    def test_fresh_install_preserves_yaml_and_sets_private_permissions(self) -> None:
        module = hindsight_module()
        targets = (
            self.write_target("default"),
            self.write_target("nancy", config="model:\n  name: nancy\n"),
        )
        transaction = RecordingTransaction()

        module.install_hindsight_configurations(targets, transaction)

        self.assertEqual(
            transaction.reservations,
            [target / "hindsight" for _profile, target in targets],
        )
        for profile, target in targets:
            with self.subTest(profile=profile):
                config_path = target / "config.yaml"
                config = yaml.safe_load(config_path.read_text(encoding="utf-8"))
                self.assertEqual(config["memory"]["provider"], "hindsight")
                self.assertEqual(config["model"]["name"], profile if profile == "nancy" else "test")
                if profile == "default":
                    self.assertEqual(config["memory"]["custom_policy"], "keep")
                    self.assertEqual(config["unrelated"], {"nested": True})
                directory = target / "hindsight"
                json_path = directory / "config.json"
                self.assertEqual(stat.S_IMODE(config_path.stat().st_mode), 0o600)
                self.assertEqual(stat.S_IMODE(directory.stat().st_mode), 0o700)
                self.assertEqual(stat.S_IMODE(json_path.stat().st_mode), 0o600)
                self.assertEqual(json.loads(json_path.read_text(encoding="utf-8")), EXPECTED_HINDSIGHT)
                self.assertTrue(json_path.read_bytes().endswith(b"\n"))

    def test_preserves_unknown_json_keys_and_overwrites_only_managed_keys(self) -> None:
        target = self.write_target("default")
        directory = target[1] / "hindsight"
        directory.mkdir(mode=0o755)
        json_path = directory / "config.json"
        json_path.write_text(
            json.dumps(
                {
                    "mode": "legacy",
                    "api_url": "https://wrong.invalid",
                    "custom": {"label": "記憶"},
                    "unknown_flag": False,
                }
            ),
            encoding="utf-8",
        )
        json_path.chmod(0o644)

        self.install((target,))

        installed = json.loads(json_path.read_text(encoding="utf-8"))
        self.assertEqual(installed, {"custom": {"label": "記憶"}, "unknown_flag": False, **EXPECTED_HINDSIGHT})
        self.assertEqual(
            json_path.read_text(encoding="utf-8"),
            json.dumps(installed, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        )
        self.assertEqual(stat.S_IMODE(directory.stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE(json_path.stat().st_mode), 0o600)

    def test_second_apply_is_byte_identical_and_does_not_snapshot(self) -> None:
        target = self.write_target("default")
        self.install((target,))
        config_path = target[1] / "config.yaml"
        json_path = target[1] / "hindsight" / "config.json"
        expected = (config_path.read_bytes(), json_path.read_bytes())
        transaction = RecordingTransaction()

        hindsight_module().install_hindsight_configurations((target,), transaction)

        self.assertEqual(transaction.snapshots, [])
        self.assertEqual(transaction.reservations, [])
        self.assertEqual((config_path.read_bytes(), json_path.read_bytes()), expected)

    def test_rejects_unsafe_filesystem_objects_without_touching_external_data(self) -> None:
        cases = (
            "yaml-symlink",
            "yaml-hardlink",
            "hindsight-symlink",
            "hindsight-file",
            "json-symlink",
            "json-hardlink",
        )
        for case in cases:
            with self.subTest(case=case), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary).resolve() / "data"
                root.mkdir(mode=0o700)
                target = root / "profiles" / "nancy"
                target.mkdir(parents=True)
                config_path = target / "config.yaml"
                config_path.write_text("model:\n  name: nancy\n", encoding="utf-8")
                outside = root.parent / "outside"
                outside.write_text("external-data", encoding="utf-8")
                directory = target / "hindsight"
                json_path = directory / "config.json"
                if case == "yaml-symlink":
                    config_path.unlink()
                    config_path.symlink_to(outside)
                elif case == "yaml-hardlink":
                    config_path.unlink()
                    os.link(outside, config_path)
                elif case == "hindsight-symlink":
                    directory.symlink_to(root.parent, target_is_directory=True)
                elif case == "hindsight-file":
                    directory.write_text("not a directory", encoding="utf-8")
                else:
                    directory.mkdir(mode=0o700)
                    if case == "json-symlink":
                        json_path.symlink_to(outside)
                    else:
                        os.link(outside, json_path)
                tx = Transaction.begin(root)
                with self.assertRaisesRegex(
                    ApplyError,
                    "could not reconcile Hermes Hindsight configuration",
                ):
                    hindsight_module().install_hindsight_configurations(
                        (("nancy", target),), tx
                    )
                tx.rollback()
                self.assertEqual(outside.read_text(encoding="utf-8"), "external-data")

    def test_rejects_malformed_or_non_mapping_yaml(self) -> None:
        for content in ("memory: [\n", "- list\n- is-not-a-mapping\n"):
            with self.subTest(content=content), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary).resolve() / "data"
                root.mkdir(mode=0o700)
                config_path = root / "config.yaml"
                config_path.write_text(content, encoding="utf-8")
                tx = Transaction.begin(root)
                try:
                    with self.assertRaisesRegex(
                        ApplyError,
                        "could not reconcile Hermes Hindsight configuration",
                    ):
                        hindsight_module().install_hindsight_configurations(
                            (("default", root),), tx
                        )
                finally:
                    tx.rollback()

    def test_rejects_malformed_or_non_mapping_json(self) -> None:
        for content in ("{\n", "[]\n", '{"custom": NaN}\n'):
            with self.subTest(content=content), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary).resolve() / "data"
                root.mkdir(mode=0o700)
                (root / "config.yaml").write_text(
                    "model:\n  name: test\n", encoding="utf-8"
                )
                directory = root / "hindsight"
                directory.mkdir(mode=0o700)
                (directory / "config.json").write_text(content, encoding="utf-8")
                tx = Transaction.begin(root)
                try:
                    with self.assertRaisesRegex(
                        ApplyError,
                        "could not reconcile Hermes Hindsight configuration",
                    ):
                        hindsight_module().install_hindsight_configurations(
                            (("default", root),), tx
                        )
                finally:
                    tx.rollback()

    def test_mid_apply_failure_rolls_back_every_previous_mutation(self) -> None:
        module = hindsight_module()
        targets = (self.write_target("default"), self.write_target("nancy"))
        before: dict[Path, tuple[bytes, int]] = {}
        for _profile, target in targets:
            directory = target / "hindsight"
            directory.mkdir(mode=0o755)
            json_path = directory / "config.json"
            json_path.write_text('{"custom":"original"}\n', encoding="utf-8")
            json_path.chmod(0o640)
            for path in (target / "config.yaml", json_path, directory):
                before[path] = (
                    b"" if path.is_dir() else path.read_bytes(),
                    stat.S_IMODE(path.stat().st_mode),
                )
        failing_path = targets[1][1] / "hindsight" / "config.json"
        original_atomic_write = module._atomic_write

        def fail_second_json(path: Path, content: bytes, mode: int) -> None:
            if path == failing_path:
                raise OSError("injected write failure")
            original_atomic_write(path, content, mode)

        tx = Transaction.begin(self.root)
        with (
            mock.patch.object(module, "_atomic_write", side_effect=fail_second_json),
            self.assertRaisesRegex(
                ApplyError,
                "could not reconcile Hermes Hindsight configuration",
            ),
        ):
            module.install_hindsight_configurations(targets, tx)
        tx.rollback()

        for path, (content, mode) in before.items():
            with self.subTest(path=path):
                self.assertEqual(stat.S_IMODE(path.stat().st_mode), mode)
                if path.is_file():
                    self.assertEqual(path.read_bytes(), content)

    def test_profile_swap_after_snapshot_cannot_redirect_the_atomic_write(
        self,
    ) -> None:
        module = hindsight_module()
        profiles = self.root / "profiles"
        profiles.mkdir()
        target = profiles / "nancy"
        tx = Transaction.begin(self.root)
        self.assertTrue(tx.reserve_directory(target))
        config_path = target / "config.yaml"
        config_path.write_bytes(
            b"model:\n"
            b"  name: reserved\n"
            b"memory:\n"
            b"  provider: legacy\n"
        )
        config_path.chmod(0o600)
        replacement = profiles / ".external-nancy"
        replacement.mkdir(mode=0o700)
        external_config = (
            b"model:\n"
            b"  name: external\n"
            b"memory:\n"
            b"  provider: external\n"
            b"  keep: untouched\n"
        )
        (replacement / "config.yaml").write_bytes(external_config)
        (replacement / "config.yaml").chmod(0o600)
        retired = profiles / ".retired-reservation"
        original_atomic_write = module._atomic_write
        swapped = False

        def swap_profile_before_atomic_write(
            path: Path | tuple[int, str],
            content: bytes,
            mode: int,
        ) -> None:
            nonlocal swapped
            destination = path[1] if isinstance(path, tuple) else path
            if not swapped and Path(destination).name == "config.yaml":
                target.rename(retired)
                replacement.rename(target)
                swapped = True
            original_atomic_write(path, content, mode)

        try:
            with mock.patch.object(
                module,
                "_atomic_write",
                side_effect=swap_profile_before_atomic_write,
            ):
                try:
                    module.install_hindsight_configurations(
                        (("nancy", target),),
                        tx,
                    )
                except ApplyError as error:
                    self.assertEqual(
                        str(error),
                        "could not reconcile Hermes Hindsight configuration",
                    )
        finally:
            tx.rollback()

        external_target = target if swapped else replacement
        self.assertEqual(
            (external_target / "config.yaml").read_bytes(),
            external_config,
        )

    def test_validation_requires_canonical_private_state_for_every_target(self) -> None:
        module = hindsight_module()
        targets = (self.write_target("default"), self.write_target("nancy"))
        self.install(targets)

        module.validate_hindsight_installation(targets)

        config_path = targets[1][1] / "config.yaml"
        config = yaml.safe_load(config_path.read_text(encoding="utf-8"))
        config["memory"]["provider"] = "legacy"
        config_path.write_text(yaml.safe_dump(config, sort_keys=False), encoding="utf-8")
        config_path.chmod(0o600)
        with self.assertRaisesRegex(
            ValidationError,
            "installed Hermes Hindsight configuration is invalid",
        ):
            module.validate_hindsight_installation(targets)

    def test_validation_rejects_public_modes_and_unsafe_links(self) -> None:
        module = hindsight_module()
        target = self.write_target("default")
        self.install((target,))
        config_path = target[1] / "config.yaml"
        directory = target[1] / "hindsight"
        json_path = directory / "config.json"

        for path in (config_path, directory, json_path):
            with self.subTest(path=path):
                original_mode = stat.S_IMODE(path.stat().st_mode)
                path.chmod(0o755 if path.is_dir() else 0o644)
                with self.assertRaises(ValidationError):
                    module.validate_hindsight_installation((target,))
                path.chmod(original_mode)

        original = json_path.read_bytes()
        json_path.unlink()
        outside = self.root.parent / "outside-json"
        outside.write_bytes(original)
        outside.chmod(0o600)
        json_path.symlink_to(outside)
        with self.assertRaises(ValidationError):
            module.validate_hindsight_installation((target,))


if __name__ == "__main__":
    unittest.main()
