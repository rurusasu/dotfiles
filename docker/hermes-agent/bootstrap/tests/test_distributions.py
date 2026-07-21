from __future__ import annotations

import json
import os
import shutil
import socket
import stat
import sys
import tempfile
import unittest
from pathlib import Path, PurePosixPath
from types import FrameType, TracebackType
from unittest import mock


BOOTSTRAP_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BOOTSTRAP_ROOT))

from hermes_bootstrap.distributions import (
    ChangeSet,
    RootDistributionManifest,
    apply_profile_distribution,
    apply_root_distribution,
    build_sanitized_profile_source,
    load_root_manifest,
)
from hermes_bootstrap.errors import ApplyError
from hermes_bootstrap.git import StagedSource
from hermes_bootstrap.models import DistributionSource


class RecordingTransaction:
    def __init__(self) -> None:
        self.snapshots: list[Path] = []

    def snapshot(self, path: Path) -> None:
        self.snapshots.append(path)


class DistributionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.data_root = self.root / "data"
        self.data_root.mkdir()
        self.stage_root = self.root / "stage"
        self.stage_root.mkdir()

    def source(self, name: str, *, root: bool = False) -> StagedSource:
        declaration = DistributionSource(
            name,
            f"https://github.com/rurusasu/hermes-{'home' if root else f'profile-{name}'}.git",
            "main",
            self.data_root if root else self.data_root / "profiles" / name,
            "root-distribution.yaml" if root else "distribution.yaml",
        )
        return StagedSource(declaration, self.stage_root, "a" * 40)

    def write_root_manifest(self, owned: list[str], **overrides: object) -> None:
        data: dict[str, object] = {
            "schema_version": 1,
            "name": "default",
            "version": "0.1.0",
            "hermes_requires": ">=0.18.2",
            "distribution_owned": owned,
        }
        data.update(overrides)
        self.write_yaml(self.stage_root / "root-distribution.yaml", data)

    def write_profile_manifest(self, name: str, owned: list[str], **overrides: object) -> None:
        data: dict[str, object] = {
            "name": name,
            "version": "0.1.0",
            "hermes_requires": ">=0.18.2",
            "distribution_owned": owned,
        }
        data.update(overrides)
        self.write_yaml(self.stage_root / "distribution.yaml", data)

    def write_yaml(self, path: Path, data: dict[str, object]) -> None:
        import yaml

        path.write_text(yaml.safe_dump(data, sort_keys=False), encoding="utf-8")

    def assert_apply_error(self, callback: object) -> None:
        with self.assertRaises(ApplyError):
            callback()

    def test_root_manifest_is_immutable_and_normalizes_owned_paths(self) -> None:
        (self.stage_root / "docs").mkdir()
        (self.stage_root / "docs" / "guide.md").write_text("guide\n", encoding="utf-8")
        self.write_root_manifest(["docs/"])

        manifest = load_root_manifest(self.stage_root)

        self.assertEqual(
            manifest,
            RootDistributionManifest(1, "default", "0.1.0", ">=0.18.2", (PurePosixPath("docs"),)),
        )
        with self.assertRaises((AttributeError, TypeError)):
            manifest.name = "other"  # type: ignore[misc]

    def test_root_manifest_rejects_duplicate_unknown_missing_and_incompatible_yaml(self) -> None:
        cases = (
            "schema_version: 1\nname: default\nname: duplicate\nversion: 0.1.0\nhermes_requires: '>=0.18.2'\ndistribution_owned: []\n",
            "schema_version: 1\nname: default\nversion: 0.1.0\nhermes_requires: '>=0.18.2'\ndistribution_owned: []\nunknown: nope\n",
            "schema_version: 1\nname: default\nversion: 0.1.0\ndistribution_owned: []\n",
            "schema_version: 1\nname: default\nversion: 0.1.0\nhermes_requires: '>99.0.0'\ndistribution_owned: []\n",
        )
        for content in cases:
            with self.subTest(content=content):
                (self.stage_root / "root-distribution.yaml").write_text(content, encoding="utf-8")
                self.assert_apply_error(lambda: load_root_manifest(self.stage_root))

    def test_root_manifest_rejects_bad_identity_and_ownership_shapes(self) -> None:
        for overrides in (
            {"schema_version": 2},
            {"name": "rick"},
            {"version": ""},
            {"description": 1},
            {"distribution_owned": "config.yaml"},
            {"distribution_owned": [1]},
        ):
            with self.subTest(overrides=overrides):
                self.write_root_manifest([], **overrides)
                self.assert_apply_error(lambda: load_root_manifest(self.stage_root))

    def test_profile_apply_does_not_follow_a_managed_destination_symlink(self) -> None:
        (self.stage_root / "config.yaml").write_text("new config\n", encoding="utf-8")
        self.write_profile_manifest("rick", ["config.yaml"])
        target = self.data_root / "profiles" / "rick"
        target.mkdir(parents=True)
        outside = self.root / "outside"
        outside.write_text("outside\n", encoding="utf-8")
        (target / "config.yaml").symlink_to(outside)

        self.assert_apply_error(lambda: apply_profile_distribution(self.source("rick"), self.data_root, RecordingTransaction()))

        self.assertEqual(outside.read_text(encoding="utf-8"), "outside\n")

    def test_profile_apply_snapshots_env_example_for_a_declared_template(self) -> None:
        (self.stage_root / ".env.template").write_text("DECLARED=value\n", encoding="utf-8")
        self.write_profile_manifest("rick", [".env.template"])
        target = self.data_root / "profiles" / "rick"
        target.mkdir(parents=True)
        tx = RecordingTransaction()

        apply_profile_distribution(self.source("rick"), self.data_root, tx)

        self.assertIn(target / ".env.EXAMPLE", tx.snapshots)
        self.assertEqual((target / ".env.EXAMPLE").read_text(encoding="utf-8"), "DECLARED=value\n")

    def test_root_manifest_rejects_unsafe_missing_overlapping_and_reserved_owned_paths(self) -> None:
        (self.stage_root / "docs").mkdir()
        (self.stage_root / "docs" / "guide.md").write_text("guide\n", encoding="utf-8")
        (self.stage_root / "config.yaml").write_text("config\n", encoding="utf-8")
        invalid = (
            ["missing"],
            ["docs", "docs/guide.md"],
            ["docs/", "docs"],
            ["../outside"],
            ["/absolute"],
            ["C:\\windows"],
            [".env"],
            ["profiles/rick/config.yaml"],
            ["cache/item"],
            ["oauth/state"],
            ["auth.json"],
        )
        for owned in invalid:
            with self.subTest(owned=owned):
                self.write_root_manifest(list(owned))
                self.assert_apply_error(lambda: load_root_manifest(self.stage_root))

    def test_root_manifest_rejects_symlink_and_special_files_at_every_depth(self) -> None:
        (self.stage_root / "directory").mkdir()
        (self.stage_root / "directory" / "real").write_text("real\n", encoding="utf-8")
        (self.stage_root / "directory" / "link").symlink_to("real")
        self.write_root_manifest(["directory"])
        self.assert_apply_error(lambda: load_root_manifest(self.stage_root))

        (self.stage_root / "directory" / "link").unlink()
        fifo = self.stage_root / "fifo"
        os.mkfifo(fifo)
        self.write_root_manifest(["fifo"])
        self.assert_apply_error(lambda: load_root_manifest(self.stage_root))

        fifo.unlink()
        special = self.stage_root / "socket"
        with socket.socket(socket.AF_UNIX) as listener:
            listener.bind(str(special))
            self.write_root_manifest(["socket"])
            self.assert_apply_error(lambda: load_root_manifest(self.stage_root))

    def test_root_apply_preserves_unowned_removes_old_owned_and_writes_canonical_state(self) -> None:
        (self.stage_root / "config.yaml").write_text("new config\n", encoding="utf-8")
        (self.stage_root / "scripts").mkdir()
        script = self.stage_root / "scripts" / "run.sh"
        script.write_text("#!/bin/sh\n", encoding="utf-8")
        script.chmod(0o755)
        self.write_root_manifest(["config.yaml", "scripts"])

        (self.data_root / "config.yaml").write_text("old config\n", encoding="utf-8")
        (self.data_root / "obsolete.txt").write_text("remove\n", encoding="utf-8")
        (self.data_root / "memories").mkdir()
        (self.data_root / "memories" / "keep").write_text("runtime\n", encoding="utf-8")
        state = self.data_root / ".bootstrap" / "root-distribution-state.json"
        state.parent.mkdir()
        state.write_text(
            json.dumps(
                {
                    "source": "https://github.com/rurusasu/hermes-home.git",
                    "ref": "main",
                    "commit": "b" * 40,
                    "version": "0.0.9",
                    "distribution_owned": ["config.yaml", "obsolete.txt"],
                }
            ),
            encoding="utf-8",
        )
        tx = RecordingTransaction()

        changed = apply_root_distribution(self.source("default", root=True), self.data_root, tx)

        self.assertEqual((self.data_root / "config.yaml").read_text(encoding="utf-8"), "new config\n")
        self.assertEqual(stat.S_IMODE((self.data_root / "scripts" / "run.sh").stat().st_mode), 0o755)
        self.assertFalse((self.data_root / "obsolete.txt").exists())
        self.assertEqual((self.data_root / "memories" / "keep").read_text(encoding="utf-8"), "runtime\n")
        self.assertEqual(
            state.read_text(encoding="utf-8"),
            '{"commit":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","distribution_owned":["config.yaml","scripts"],"ref":"main","source":"https://github.com/rurusasu/hermes-home.git","version":"0.1.0"}\n',
        )
        self.assertEqual(
            changed,
            ChangeSet((self.data_root / ".bootstrap" / "root-distribution-state.json", self.data_root / "config.yaml", self.data_root / "obsolete.txt", self.data_root / "scripts")),
        )
        self.assertEqual(tx.snapshots, [self.data_root / "config.yaml", self.data_root / "obsolete.txt", self.data_root / "scripts", state])

    def test_root_apply_is_idempotent_and_rejects_malformed_or_unsafe_prior_state(self) -> None:
        (self.stage_root / "config.yaml").write_text("config\n", encoding="utf-8")
        self.write_root_manifest(["config.yaml"])
        first = apply_root_distribution(self.source("default", root=True), self.data_root, RecordingTransaction())
        second_tx = RecordingTransaction()
        second = apply_root_distribution(self.source("default", root=True), self.data_root, second_tx)
        self.assertTrue(first.changed_paths)
        self.assertEqual(second, ChangeSet(()))
        self.assertEqual(second_tx.snapshots, [])

        state = self.data_root / ".bootstrap" / "root-distribution-state.json"
        for content in ("not json", '{"distribution_owned":["../escape"]}'):
            with self.subTest(content=content):
                state.write_text(content, encoding="utf-8")
                self.assert_apply_error(
                    lambda: apply_root_distribution(self.source("default", root=True), self.data_root, RecordingTransaction())
                )

    def test_root_apply_rejects_unsafe_data_root_and_managed_ancestor(self) -> None:
        (self.stage_root / "config.yaml").write_text("config\n", encoding="utf-8")
        self.write_root_manifest(["config.yaml"])
        data_link = self.root / "data-link"
        data_link.symlink_to(self.data_root)
        self.assert_apply_error(lambda: apply_root_distribution(self.source("default", root=True), data_link, RecordingTransaction()))

        (self.data_root / "docs").symlink_to(self.root)
        (self.stage_root / "docs").mkdir()
        self.write_root_manifest(["docs"])
        self.assert_apply_error(lambda: apply_root_distribution(self.source("default", root=True), self.data_root, RecordingTransaction()))

    def test_root_apply_snapshots_a_missing_owned_parent_before_creating_it(self) -> None:
        (self.stage_root / "cron").mkdir()
        (self.stage_root / "cron" / "jobs.json").write_text("{}\n", encoding="utf-8")
        self.write_root_manifest(["cron/jobs.json"])
        tx = RecordingTransaction()

        apply_root_distribution(self.source("default", root=True), self.data_root, tx)

        self.assertEqual(tx.snapshots[:2], [self.data_root / "cron", self.data_root / "cron" / "jobs.json"])

    def test_root_apply_rejects_a_special_existing_managed_destination(self) -> None:
        (self.stage_root / "config.yaml").write_text("config\n", encoding="utf-8")
        self.write_root_manifest(["config.yaml"])
        target = self.data_root / "config.yaml"
        os.mkfifo(target)

        self.assert_apply_error(lambda: apply_root_distribution(self.source("default", root=True), self.data_root, RecordingTransaction()))

        self.assertTrue(stat.S_ISFIFO(target.lstat().st_mode))

    def test_sanitized_profile_source_contains_only_manifest_and_owned_payload(self) -> None:
        (self.stage_root / "config.yaml").write_text("config\n", encoding="utf-8")
        (self.stage_root / "assets").mkdir()
        (self.stage_root / "assets" / "logo.txt").write_text("logo\n", encoding="utf-8")
        (self.stage_root / ".github").mkdir()
        (self.stage_root / ".github" / "workflow.yml").write_text("tooling\n", encoding="utf-8")
        for name in (".pre-commit-config.yaml", ".gitignore"):
            (self.stage_root / name).write_text("tooling\n", encoding="utf-8")
        (self.stage_root / "scripts").mkdir()
        (self.stage_root / "scripts" / "validate_distribution.py").write_text("tooling\n", encoding="utf-8")
        (self.stage_root / "tests").mkdir()
        (self.stage_root / "tests" / "test_tool.py").write_text("tooling\n", encoding="utf-8")
        self.write_profile_manifest("rick", ["config.yaml", "assets"])

        sanitized = build_sanitized_profile_source(self.source("rick"), self.root / "scratch")

        self.assertEqual(stat.S_IMODE(sanitized.stat().st_mode), 0o700)
        self.assertEqual(sorted(path.relative_to(sanitized).as_posix() for path in sanitized.rglob("*") if path.is_file()), ["assets/logo.txt", "config.yaml", "distribution.yaml"])
        self.assertFalse((sanitized / ".github").exists())
        self.assertFalse((sanitized / "scripts").exists())

    def test_sanitized_profile_source_rejects_invalid_manifest_and_unsafe_payload(self) -> None:
        (self.stage_root / "config.yaml").write_text("config\n", encoding="utf-8")
        invalid = (
            ("other", ["config.yaml"]),
            ("rick", ["config.yaml", "config.yaml/"]),
            ("rick", ["config.yaml", "../outside"]),
            ("rick", ["config.yaml", "/absolute"]),
            ("rick", [".env"]),
        )
        for name, owned in invalid:
            with self.subTest(name=name, owned=owned):
                self.write_profile_manifest(name, owned)
                self.assert_apply_error(lambda: build_sanitized_profile_source(self.source("rick"), self.root / "scratch"))

        (self.stage_root / "nested").mkdir()
        (self.stage_root / "nested" / "value").write_text("value\n", encoding="utf-8")
        (self.stage_root / "nested" / "link").symlink_to("value")
        self.write_profile_manifest("rick", ["nested"])
        self.assert_apply_error(lambda: build_sanitized_profile_source(self.source("rick"), self.root / "scratch"))

    def test_sanitized_profile_source_rejects_raw_absolute_and_duplicate_owned_paths(self) -> None:
        (self.stage_root / "config.yaml").write_text("config\n", encoding="utf-8")
        manifests = (
            "name: rick\nversion: 0.1.0\nhermes_requires: '>=0.18.2'\ndistribution_owned:\n  - /config.yaml\n",
            "name: rick\nversion: 0.1.0\nhermes_requires: '>=0.18.2'\ndistribution_owned:\n  - config.yaml\ndistribution_owned: []\n",
        )
        for content in manifests:
            with self.subTest(content=content):
                (self.stage_root / "distribution.yaml").write_text(content, encoding="utf-8")
                self.assert_apply_error(lambda: build_sanitized_profile_source(self.source("rick"), self.root / "scratch"))

    def test_profile_apply_rejects_a_symlinked_profile_namespace(self) -> None:
        (self.stage_root / "config.yaml").write_text("config\n", encoding="utf-8")
        self.write_profile_manifest("rick", ["config.yaml"])
        outside = self.root / "outside"
        outside.mkdir()
        (self.data_root / "profiles").symlink_to(outside, target_is_directory=True)

        self.assert_apply_error(lambda: apply_profile_distribution(self.source("rick"), self.data_root, RecordingTransaction()))

        self.assertFalse((outside / "rick").exists())

    def test_profile_apply_uses_official_force_api_preserves_user_data_and_stamps_canonical_source(self) -> None:
        (self.stage_root / "config.yaml").write_text("new config\n", encoding="utf-8")
        (self.stage_root / "SOUL.md").write_text("new soul\n", encoding="utf-8")
        (self.stage_root / ".github").mkdir()
        (self.stage_root / ".github" / "workflow.yml").write_text("never install\n", encoding="utf-8")
        self.write_profile_manifest("rick", ["config.yaml", "SOUL.md"], env_requires=[{"name": "API_KEY", "description": "key"}])
        target = self.data_root / "profiles" / "rick"
        target.mkdir(parents=True)
        (target / "config.yaml").write_text("old config\n", encoding="utf-8")
        for name in (".env", "auth.json"):
            (target / name).write_text(f"{name} keep\n", encoding="utf-8")
        for directory in ("memories", "sessions", "logs", "workspace"):
            (target / directory).mkdir()
            (target / directory / "keep").write_text(directory, encoding="utf-8")
        tx = RecordingTransaction()
        previous_home = os.environ.get("HERMES_HOME")
        os.environ["HERMES_HOME"] = "environment-restore-marker"
        self.addCleanup(self.restore_environment, "HERMES_HOME", previous_home)

        changed = apply_profile_distribution(self.source("rick"), self.data_root, tx)

        self.assertEqual((target / "config.yaml").read_text(encoding="utf-8"), "new config\n")
        self.assertEqual((target / "SOUL.md").read_text(encoding="utf-8"), "new soul\n")
        self.assertFalse((target / ".github").exists())
        for name in (".env", "auth.json"):
            self.assertEqual((target / name).read_text(encoding="utf-8"), f"{name} keep\n")
        for directory in ("memories", "sessions", "logs", "workspace"):
            self.assertEqual((target / directory / "keep").read_text(encoding="utf-8"), directory)
        self.assertEqual(os.environ["HERMES_HOME"], "environment-restore-marker")
        manifest = (target / "distribution.yaml").read_text(encoding="utf-8")
        self.assertIn("source: https://github.com/rurusasu/hermes-profile-rick.git", manifest)
        self.assertNotIn(str(self.root / "scratch"), manifest)
        self.assertEqual(changed, ChangeSet(tuple(sorted(set(tx.snapshots), key=lambda path: path.as_posix()))))
        self.assertIn(target / "config.yaml", tx.snapshots)
        self.assertIn(target / "distribution.yaml", tx.snapshots)
        self.assertIn(target / ".env.EXAMPLE", tx.snapshots)
        self.assertIn(target / "skills", tx.snapshots)
        self.assertIn(target / "skins", tx.snapshots)
        self.assertIn(target / "cron", tx.snapshots)

    def test_profile_apply_snapshots_absent_target_and_restores_environment_on_failure(self) -> None:
        (self.stage_root / "config.yaml").write_text("config\n", encoding="utf-8")
        self.write_profile_manifest("rick", ["config.yaml"])
        tx = RecordingTransaction()
        previous_home = os.environ.pop("HERMES_HOME", None)
        self.addCleanup(self.restore_environment, "HERMES_HOME", previous_home)

        with mock.patch("hermes_bootstrap.distributions.profile_distribution.install_distribution", side_effect=RuntimeError("staged-secret-marker")):
            with self.assertRaises(ApplyError) as caught:
                apply_profile_distribution(self.source("rick"), self.data_root, tx)

        target = self.data_root / "profiles" / "rick"
        self.assertEqual(tx.snapshots, [target])
        self.assertNotIn("HERMES_HOME", os.environ)
        self.assertEqual(str(caught.exception), "could not apply the named profile distribution")
        self.assert_exception_hides_markers(caught.exception, "staged-secret-marker", str(self.stage_root))

    def test_profile_cleanup_failure_does_not_replace_or_expose_primary_failure(self) -> None:
        (self.stage_root / "config.yaml").write_text("config\n", encoding="utf-8")
        self.write_profile_manifest("rick", ["config.yaml"])
        original_rmtree = shutil.rmtree

        def remove_or_fail(path: object, *args: object, **kwargs: object) -> None:
            if "scratch" in str(path):
                raise OSError("cleanup-secret-marker")
            original_rmtree(path, *args, **kwargs)

        with mock.patch("hermes_bootstrap.distributions.profile_distribution.install_distribution", side_effect=RuntimeError("primary-secret-marker")):
            with mock.patch("hermes_bootstrap.distributions.shutil.rmtree", side_effect=remove_or_fail):
                with self.assertRaises(ApplyError) as caught:
                    apply_profile_distribution(self.source("rick"), self.data_root, RecordingTransaction())

        self.assertEqual(str(caught.exception), "could not apply the named profile distribution")
        self.assert_exception_hides_markers(caught.exception, "primary-secret-marker", "cleanup-secret-marker", str(self.stage_root))

    def test_profile_cleanup_failure_after_success_is_safely_reported(self) -> None:
        (self.stage_root / "config.yaml").write_text("config\n", encoding="utf-8")
        self.write_profile_manifest("rick", ["config.yaml"])
        original_rmtree = shutil.rmtree

        def remove_or_fail(path: object, *args: object, **kwargs: object) -> None:
            if Path(path).name.startswith("profile-"):
                raise OSError("successful-cleanup-secret-marker")
            original_rmtree(path, *args, **kwargs)

        with mock.patch("hermes_bootstrap.distributions.shutil.rmtree", side_effect=remove_or_fail):
            with self.assertRaises(ApplyError) as caught:
                apply_profile_distribution(self.source("rick"), self.data_root, RecordingTransaction())

        self.assertEqual(str(caught.exception), "could not clean up the named profile distribution")
        self.assert_exception_hides_markers(caught.exception, "successful-cleanup-secret-marker", str(self.stage_root))

    def test_changeset_is_immutable_deterministic_and_content_free(self) -> None:
        changes = ChangeSet((self.root / "b", self.root / "a", self.root / "b"))
        self.assertEqual(changes.changed_paths, (self.root / "a", self.root / "b"))
        self.assertNotIn("content", repr(changes).lower())
        with self.assertRaises((AttributeError, TypeError)):
            changes.changed_paths = ()  # type: ignore[misc]

    def restore_environment(self, key: str, value: str | None) -> None:
        if value is None:
            os.environ.pop(key, None)
        else:
            os.environ[key] = value

    def assert_exception_hides_markers(self, error: BaseException, *markers: str) -> None:
        pending: list[object] = [error]
        visited: set[int] = set()
        while pending:
            value = pending.pop()
            if id(value) in visited:
                continue
            visited.add(id(value))
            if isinstance(value, str):
                for marker in markers:
                    self.assertNotIn(marker, value)
            elif isinstance(value, bytes):
                for marker in markers:
                    self.assertNotIn(marker.encode("utf-8"), value)
            elif isinstance(value, BaseException):
                pending.extend((value.__cause__, value.__context__, value.__traceback__, value.args))
            elif isinstance(value, TracebackType):
                pending.extend((value.tb_frame, value.tb_next))
            elif isinstance(value, FrameType):
                if "hermes_bootstrap" in value.f_code.co_filename:
                    pending.extend(value.f_locals.values())
            elif isinstance(value, dict):
                pending.extend((*value.keys(), *value.values()))
            elif isinstance(value, (list, tuple, set, frozenset)):
                pending.extend(value)


if __name__ == "__main__":
    unittest.main()
