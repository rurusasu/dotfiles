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

from hermes_bootstrap import distributions
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
from hermes_bootstrap.transaction import Transaction as DurableTransaction


class RecordingTransaction:
    def __init__(self) -> None:
        self.snapshots: list[Path] = []
        self.reservations: list[Path] = []

    def snapshot(self, path: Path) -> None:
        self.snapshots.append(path)

    def reserve_directory(self, path: Path, *, remove_tree: bool = True) -> bool:
        del remove_tree
        try:
            path.mkdir()
        except FileExistsError:
            return False
        self.reservations.append(path)
        return True


class StrictRecordingTransaction(RecordingTransaction):
    def snapshot(self, path: Path) -> None:
        if path in self.snapshots:
            raise AssertionError(f"duplicate snapshot: {path}")
        super().snapshot(path)


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

    def write_profile_manifest(self, profile_name: str, owned: list[str], **overrides: object) -> None:
        data: dict[str, object] = {
            "name": profile_name,
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

    def test_root_manifest_rejects_whitespace_version_before_writes(self) -> None:
        self.write_root_manifest([], version=" 0.1.0")

        self.assert_apply_error(lambda: apply_root_distribution(self.source("default", root=True), self.data_root, RecordingTransaction()))

        self.assertFalse((self.data_root / ".bootstrap").exists())

    def test_root_manifest_rejects_empty_or_whitespace_hermes_requires_before_writes(self) -> None:
        for index, hermes_requires in enumerate(("", " >=0.18.2", ">=0.18.2 ")):
            with self.subTest(hermes_requires=hermes_requires):
                self.data_root = self.root / f"root-{index}"
                self.data_root.mkdir()
                self.write_root_manifest([], hermes_requires=hermes_requires)

                self.assert_apply_error(
                    lambda: apply_root_distribution(self.source("default", root=True), self.data_root, RecordingTransaction())
                )

                self.assertFalse((self.data_root / ".bootstrap").exists())

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

    def test_profile_rejects_env_template_mapping_collisions_and_invalid_template_shapes(self) -> None:
        cases = (
            ("mapped-destinations", [".env.template", ".env.EXAMPLE"], {".env.template": "file", ".env.EXAMPLE": "file"}),
            ("mapped-overlap", [".env.template", ".env.EXAMPLE/nested"], {".env.template": "file", ".env.EXAMPLE": "directory"}),
            ("nested-template", [".env.template/nested"], {".env.template": "directory"}),
            ("directory-template", [".env.template"], {".env.template": "directory"}),
        )
        for name, owned, paths in cases:
            with self.subTest(name=name):
                shutil.rmtree(self.stage_root)
                self.stage_root.mkdir()
                for path, kind in paths.items():
                    source = self.stage_root / path
                    if kind == "directory":
                        source.mkdir()
                        (source / "nested").write_text("nested\n", encoding="utf-8")
                    else:
                        source.write_text("template\n", encoding="utf-8")
                self.write_profile_manifest("rick", list(owned))

                with mock.patch("hermes_bootstrap.distributions.profile_distribution.install_distribution") as install:
                    self.assert_apply_error(lambda: apply_profile_distribution(self.source("rick"), self.data_root, RecordingTransaction()))

                install.assert_not_called()
                self.assertFalse((self.data_root / "profiles" / "rick").exists())

    def test_profile_template_install_is_deterministic_and_second_apply_is_a_noop(self) -> None:
        (self.stage_root / ".env.template").write_text("DECLARED=value\n", encoding="utf-8")
        self.write_profile_manifest("rick", [".env.template"])

        first = apply_profile_distribution(self.source("rick"), self.data_root, RecordingTransaction())

        target = self.data_root / "profiles" / "rick"
        self.assertNotEqual(first, ChangeSet(()))
        self.assertFalse((target / ".env.template").exists())
        self.assertEqual((target / ".env.EXAMPLE").read_text(encoding="utf-8"), "DECLARED=value\n")
        before = {
            path: (path.read_bytes(), path.stat().st_ino)
            for path in (target / ".env.EXAMPLE", target / "distribution.yaml")
        }

        with mock.patch("hermes_bootstrap.distributions.profile_distribution.install_distribution") as install:
            second = apply_profile_distribution(self.source("rick"), self.data_root, StrictRecordingTransaction())

        self.assertEqual(second, ChangeSet(()))
        install.assert_not_called()
        self.assertEqual(
            {path: (path.read_bytes(), path.stat().st_ino) for path in before},
            before,
        )

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

    def test_root_apply_treats_previous_and_next_ownership_as_trees(self) -> None:
        state = self.data_root / ".bootstrap" / "root-distribution-state.json"
        state.parent.mkdir()

        (self.stage_root / "docs").mkdir()
        (self.stage_root / "docs" / "guide.md").write_text("new guide\n", encoding="utf-8")
        (self.data_root / "docs").mkdir()
        (self.data_root / "docs" / "guide.md").write_text("old guide\n", encoding="utf-8")
        state.write_text(self.root_state(["docs/guide.md"]), encoding="utf-8")
        self.write_root_manifest(["docs"])

        apply_root_distribution(self.source("default", root=True), self.data_root, RecordingTransaction())

        self.assertEqual((self.data_root / "docs" / "guide.md").read_text(encoding="utf-8"), "new guide\n")

        shutil.rmtree(self.stage_root / "docs")
        (self.stage_root / "docs").mkdir()
        (self.stage_root / "docs" / "guide.md").write_text("child guide\n", encoding="utf-8")
        (self.data_root / "docs" / "obsolete.md").write_text("retire parent\n", encoding="utf-8")
        state.write_text(self.root_state(["docs"]), encoding="utf-8")
        self.write_root_manifest(["docs/guide.md"])

        apply_root_distribution(self.source("default", root=True), self.data_root, RecordingTransaction())

        self.assertEqual((self.data_root / "docs" / "guide.md").read_text(encoding="utf-8"), "child guide\n")
        self.assertFalse((self.data_root / "docs" / "obsolete.md").exists())

    def test_root_replace_failure_restores_existing_destination_and_retains_copy_when_restore_fails(self) -> None:
        (self.stage_root / "config.yaml").write_text("new config\n", encoding="utf-8")
        self.write_root_manifest(["config.yaml"])
        target = self.data_root / "config.yaml"
        target.write_text("old config\n", encoding="utf-8")
        original_replace = os.replace
        calls = 0

        def fail_install_once(source: object, destination: object) -> None:
            nonlocal calls
            calls += 1
            if calls == 2:
                raise OSError("install-secret-marker")
            original_replace(source, destination)

        with mock.patch("hermes_bootstrap.distributions.os.replace", side_effect=fail_install_once):
            self.assert_apply_error(lambda: apply_root_distribution(self.source("default", root=True), self.data_root, RecordingTransaction()))

        self.assertEqual(target.read_text(encoding="utf-8"), "old config\n")

        target.write_text("old config\n", encoding="utf-8")
        calls = 0

        def fail_install_and_restore(source: object, destination: object) -> None:
            nonlocal calls
            calls += 1
            if calls in (2, 3):
                raise OSError("restore-secret-marker")
            original_replace(source, destination)

        with mock.patch("hermes_bootstrap.distributions.os.replace", side_effect=fail_install_and_restore):
            with self.assertRaises(ApplyError) as caught:
                apply_root_distribution(self.source("default", root=True), self.data_root, RecordingTransaction())

        self.assertFalse(target.exists())
        retired = list(self.data_root.glob(".config.yaml.bootstrap-*"))
        self.assertEqual(len(retired), 1)
        self.assertEqual(retired[0].read_text(encoding="utf-8"), "old config\n")
        self.assert_exception_hides_markers(caught.exception, "restore-secret-marker", str(self.stage_root))

    def test_root_replace_retains_old_copy_when_post_replace_fsync_and_restore_fail(self) -> None:
        (self.stage_root / "config.yaml").write_text("new config\n", encoding="utf-8")
        self.write_root_manifest(["config.yaml"])
        target = self.data_root / "config.yaml"
        target.write_text("old config\n", encoding="utf-8")
        original_replace = os.replace
        replace_calls = 0

        def fail_restore(source: object, destination: object) -> None:
            nonlocal replace_calls
            replace_calls += 1
            if replace_calls == 3:
                raise OSError("restore-secret-marker")
            original_replace(source, destination)

        def fail_post_replace_fsync(path: Path) -> None:
            if path == self.data_root and target.exists() and target.read_text(encoding="utf-8") == "new config\n":
                raise OSError("post-replace-fsync-secret-marker")

        with mock.patch("hermes_bootstrap.distributions.os.replace", side_effect=fail_restore):
            with mock.patch("hermes_bootstrap.distributions._fsync_parent", side_effect=fail_post_replace_fsync):
                with self.assertRaises(ApplyError) as caught:
                    apply_root_distribution(self.source("default", root=True), self.data_root, RecordingTransaction())

        self.assertEqual(target.read_text(encoding="utf-8"), "new config\n")
        retired = list(self.data_root.glob(".config.yaml.bootstrap-*"))
        self.assertEqual(len(retired), 1)
        self.assertEqual(retired[0].read_text(encoding="utf-8"), "old config\n")
        self.assert_exception_hides_markers(caught.exception, "restore-secret-marker", "post-replace-fsync-secret-marker", str(self.stage_root))

    def test_root_parent_to_child_transition_uses_one_snapshot_coverage(self) -> None:
        state = self.data_root / ".bootstrap" / "root-distribution-state.json"
        state.parent.mkdir()
        state.write_text(self.root_state(["docs"]), encoding="utf-8")
        (self.data_root / "docs").mkdir()
        (self.data_root / "docs" / "obsolete.txt").write_text("old\n", encoding="utf-8")
        (self.stage_root / "docs").mkdir()
        (self.stage_root / "docs" / "guide.md").write_text("new\n", encoding="utf-8")
        self.write_root_manifest(["docs/guide.md"])
        tx = StrictRecordingTransaction()

        apply_root_distribution(self.source("default", root=True), self.data_root, tx)

        self.assertEqual((self.data_root / "docs" / "guide.md").read_text(encoding="utf-8"), "new\n")
        self.assertEqual(tx.snapshots.count(self.data_root / "docs"), 1)

    def test_root_remove_failure_restores_existing_destination(self) -> None:
        (self.stage_root / "config.yaml").write_text("new config\n", encoding="utf-8")
        self.write_root_manifest(["config.yaml"])
        target = self.data_root / "obsolete.txt"
        target.write_text("retired config\n", encoding="utf-8")
        state = self.data_root / ".bootstrap" / "root-distribution-state.json"
        state.parent.mkdir()
        state.write_text(self.root_state(["obsolete.txt"]), encoding="utf-8")

        from hermes_bootstrap.distributions import _remove_raw as original_remove

        def fail_retired_copy(path: Path) -> None:
            if path.read_text(encoding="utf-8") == "retired config\n":
                raise OSError("remove-secret-marker")
            original_remove(path)

        with mock.patch("hermes_bootstrap.distributions._remove_raw", side_effect=fail_retired_copy):
            with self.assertRaises(ApplyError) as caught:
                apply_root_distribution(self.source("default", root=True), self.data_root, RecordingTransaction())

        self.assertEqual(target.read_text(encoding="utf-8"), "retired config\n")
        self.assert_exception_hides_markers(caught.exception, "remove-secret-marker", str(self.stage_root))

    def test_root_apply_rejects_strict_unsafe_prior_state_metadata(self) -> None:
        (self.stage_root / "config.yaml").write_text("config\n", encoding="utf-8")
        self.write_root_manifest(["config.yaml"])
        state = self.data_root / ".bootstrap" / "root-distribution-state.json"
        state.parent.mkdir()
        valid = json.loads(self.root_state(["obsolete.txt"]))
        invalid = (
            {**valid, "source": "https://token@github.com/rurusasu/hermes-home.git"},
            {**valid, "source": "https://example.com/rurusasu/hermes-home.git"},
            {**valid, "ref": "refs//heads/main"},
            {**valid, "commit": "A" * 40},
            {**valid, "version": " 0.1.0"},
            {**valid, "distribution_owned": [" config.yaml"]},
        )
        for raw in invalid:
            with self.subTest(raw=raw):
                state.write_text(json.dumps(raw), encoding="utf-8")
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

        self.assertEqual(tx.snapshots, [self.data_root / "cron", self.data_root / ".bootstrap"])

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

    def test_profile_rejects_the_transaction_reservation_marker(self) -> None:
        marker = self.stage_root / ".bootstrap-reservation"
        marker.write_text("distribution-owned\n", encoding="utf-8")
        self.write_profile_manifest("rick", [marker.name])

        self.assert_apply_error(
            lambda: build_sanitized_profile_source(
                self.source("rick"),
                self.root / "scratch",
            )
        )

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

    def test_root_and_profile_reject_runtime_owned_namespaces_but_root_allows_skills_and_cron(self) -> None:
        for name in (".browser", "browser_screenshots", "workspace", "home", "plans", "audio_cache", "document_cache", "image_cache"):
            with self.subTest(root=name):
                (self.stage_root / name).mkdir(exist_ok=True)
                self.write_root_manifest([name])
                self.assert_apply_error(lambda: load_root_manifest(self.stage_root))

        for name in ("workspace", "home", "plans", "audio_cache", "document_cache", "image_cache", "browser_screenshots"):
            with self.subTest(profile=name):
                (self.stage_root / name).mkdir(exist_ok=True)
                self.write_profile_manifest("rick", [f"{name}/payload"])
                (self.stage_root / name / "payload").write_text("blocked\n", encoding="utf-8")
                self.assert_apply_error(lambda: build_sanitized_profile_source(self.source("rick"), self.root / "scratch"))

        for name in ("skills", "cron"):
            (self.stage_root / name).mkdir(exist_ok=True)
            (self.stage_root / name / "payload").write_text("allowed\n", encoding="utf-8")
        self.write_root_manifest(["skills", "cron"])
        self.assertEqual(load_root_manifest(self.stage_root).distribution_owned, (PurePosixPath("cron"), PurePosixPath("skills")))

    def test_profile_preflight_snapshots_missing_parents_and_bootstrap_directories(self) -> None:
        (self.stage_root / "config.yaml").write_text("config\n", encoding="utf-8")
        self.write_profile_manifest("rick", ["config.yaml"])
        tx = RecordingTransaction()

        with mock.patch("hermes_bootstrap.distributions.profile_distribution.install_distribution", side_effect=RuntimeError("preflight-secret-marker")):
            with self.assertRaises(ApplyError) as caught:
                apply_profile_distribution(self.source("rick"), self.data_root, tx)

        self.assertEqual(tx.snapshots, [self.data_root / "profiles"])
        self.assert_exception_hides_markers(caught.exception, "preflight-secret-marker", str(self.stage_root))

    def test_profile_apply_is_a_true_identical_noop_before_official_install(self) -> None:
        (self.stage_root / "config.yaml").write_text("config\n", encoding="utf-8")
        (self.stage_root / "assets").mkdir()
        (self.stage_root / "assets" / "script.sh").write_text("#!/bin/sh\n", encoding="utf-8")
        (self.stage_root / "assets" / "script.sh").chmod(0o755)
        self.write_profile_manifest("rick", ["config.yaml", "assets"], env_requires=[{"name": "API_KEY", "description": "key"}])
        apply_profile_distribution(self.source("rick"), self.data_root, RecordingTransaction())
        target = self.data_root / "profiles" / "rick"
        manifest_before = (target / "distribution.yaml").read_text(encoding="utf-8")
        inodes = {path: path.stat().st_ino for path in (target / "config.yaml", target / "assets", target / "distribution.yaml")}

        with mock.patch("hermes_bootstrap.distributions.profile_distribution.install_distribution") as install:
            changed = apply_profile_distribution(self.source("rick"), self.data_root, RecordingTransaction())

        self.assertEqual(changed, ChangeSet(()))
        install.assert_not_called()
        self.assertEqual((target / "distribution.yaml").read_text(encoding="utf-8"), manifest_before)
        self.assertEqual({path: path.stat().st_ino for path in inodes}, inodes)

    def test_profile_no_overwrite_installs_a_still_missing_target(self) -> None:
        (self.stage_root / "config.yaml").write_text("config\n", encoding="utf-8")
        self.write_profile_manifest("rick", ["config.yaml"])

        changed = apply_profile_distribution(
            self.source("rick"),
            self.data_root,
            RecordingTransaction(),
            replace_existing=False,
        )

        target = self.data_root / "profiles" / "rick"
        self.assertNotEqual(changed, ChangeSet(()))
        self.assertEqual((target / "config.yaml").read_text(encoding="utf-8"), "config\n")

    def test_profile_no_overwrite_rejects_a_target_created_after_the_missing_probe(
        self,
    ) -> None:
        (self.stage_root / "config.yaml").write_text("staged\n", encoding="utf-8")
        self.write_profile_manifest("rick", ["config.yaml"])
        target = self.data_root / "profiles" / "rick"
        tx = DurableTransaction.begin(self.data_root)
        real_is_current = distributions._profile_is_current
        external_before: dict[str, tuple[int, bytes | None]] | None = None

        def is_current_then_create(*args: object, **kwargs: object) -> bool:
            nonlocal external_before
            result = real_is_current(*args, **kwargs)
            target.mkdir(parents=True)
            (target / "config.yaml").write_bytes(b"external\n")
            (target / "config.yaml").chmod(0o600)
            external_before = {
                path.relative_to(target).as_posix(): (
                    stat.S_IMODE(path.stat().st_mode),
                    None if path.is_dir() else path.read_bytes(),
                )
                for path in (target, *sorted(target.rglob("*")))
            }
            return result

        with (
            mock.patch.object(
                distributions,
                "_profile_is_current",
                side_effect=is_current_then_create,
            ),
            mock.patch(
                "hermes_bootstrap.distributions.profile_distribution.install_distribution"
            ) as install,
            self.assertRaises(ApplyError),
        ):
            apply_profile_distribution(
                self.source("rick"),
                self.data_root,
                tx,
                replace_existing=False,
            )

        tx.rollback()
        self.assertIsNotNone(external_before)
        self.assertEqual(
            {
                path.relative_to(target).as_posix(): (
                    stat.S_IMODE(path.stat().st_mode),
                    None if path.is_dir() else path.read_bytes(),
                )
                for path in (target, *sorted(target.rglob("*")))
            },
            external_before,
        )
        install.assert_not_called()

    def test_profile_no_overwrite_allows_a_byte_identical_existing_target(
        self,
    ) -> None:
        (self.stage_root / "config.yaml").write_text("config\n", encoding="utf-8")
        self.write_profile_manifest("rick", ["config.yaml"])
        apply_profile_distribution(
            self.source("rick"),
            self.data_root,
            RecordingTransaction(),
        )
        tx = RecordingTransaction()

        with mock.patch(
            "hermes_bootstrap.distributions.profile_distribution.install_distribution"
        ) as install:
            changed = apply_profile_distribution(
                self.source("rick"),
                self.data_root,
                tx,
                replace_existing=False,
            )

        self.assertEqual(changed, ChangeSet(()))
        self.assertEqual(tx.snapshots, [])
        install.assert_not_called()

    def test_profile_no_overwrite_rejects_differing_and_malformed_existing_targets_without_mutation(
        self,
    ) -> None:
        (self.stage_root / "config.yaml").write_text("config\n", encoding="utf-8")
        self.write_profile_manifest("rick", ["config.yaml"])

        def snapshot_tree(root: Path) -> dict[
            str, tuple[str, int, bytes | None]
        ]:
            return {
                path.relative_to(root).as_posix(): (
                    "directory" if path.is_dir() else "file",
                    stat.S_IMODE(path.stat().st_mode),
                    None if path.is_dir() else path.read_bytes(),
                )
                for path in (root, *sorted(root.rglob("*")))
            }

        for condition in ("differing", "malformed"):
            with self.subTest(condition=condition):
                shutil.rmtree(self.data_root / "profiles", ignore_errors=True)
                apply_profile_distribution(
                    self.source("rick"),
                    self.data_root,
                    RecordingTransaction(),
                )
                target = self.data_root / "profiles" / "rick"
                if condition == "differing":
                    (target / "config.yaml").write_bytes(b"local-authoritative\n")
                    (target / "config.yaml").chmod(0o600)
                else:
                    (target / "distribution.yaml").write_bytes(
                        b"name: rick\nversion: [\n"
                    )
                    (target / "distribution.yaml").chmod(0o600)
                before = snapshot_tree(target)
                tx = RecordingTransaction()

                with (
                    mock.patch(
                        "hermes_bootstrap.distributions.profile_distribution.install_distribution"
                    ) as install,
                    self.assertRaises(ApplyError),
                ):
                    apply_profile_distribution(
                        self.source("rick"),
                        self.data_root,
                        tx,
                        replace_existing=False,
                    )

                self.assertEqual(tx.snapshots, [])
                install.assert_not_called()
                self.assertEqual(snapshot_tree(target), before)

    def test_profile_rejects_hardlinked_direct_managed_files_before_official_install(self) -> None:
        cases = (
            ("config.yaml", ["config.yaml"], "config.yaml"),
            ("env-example", [".env.template"], ".env.EXAMPLE"),
            ("manifest", ["config.yaml"], "distribution.yaml"),
            ("other-top-level", ["SOUL.md"], "SOUL.md"),
        )
        for label, owned, target_name in cases:
            with self.subTest(label=label):
                shutil.rmtree(self.stage_root)
                self.stage_root.mkdir()
                for owned_path in owned:
                    (self.stage_root / owned_path).write_text("hardlink-stage-marker\n", encoding="utf-8")
                self.write_profile_manifest("rick", list(owned))
                target = self.data_root / "profiles" / "rick"
                target.mkdir(parents=True, exist_ok=True)
                outside = self.root / f"outside-{label}"
                outside.write_text("hardlink-outside-marker\n", encoding="utf-8")
                os.link(outside, target / target_name)

                with mock.patch("hermes_bootstrap.distributions.profile_distribution.install_distribution") as install:
                    with self.assertRaises(ApplyError) as caught:
                        apply_profile_distribution(self.source("rick"), self.data_root, RecordingTransaction())

                self.assertEqual(str(caught.exception), "could not apply the named profile distribution")
                self.assertEqual(outside.read_text(encoding="utf-8"), "hardlink-outside-marker\n")
                self.assert_exception_hides_markers(
                    caught.exception,
                    "hardlink-stage-marker",
                    "hardlink-outside-marker",
                    str(self.stage_root),
                    str(outside),
                )
                install.assert_not_called()
                shutil.rmtree(target)

    def test_profile_allows_a_hardlink_inside_an_owned_directory_without_scanning_user_owned_paths(self) -> None:
        (self.stage_root / "assets").mkdir()
        (self.stage_root / "assets" / "payload.txt").write_text("old\n", encoding="utf-8")
        self.write_profile_manifest("rick", ["assets"])
        apply_profile_distribution(self.source("rick"), self.data_root, RecordingTransaction())
        target = self.data_root / "profiles" / "rick"
        outside = self.root / "outside-directory"
        outside.write_text("old\n", encoding="utf-8")
        (target / "assets" / "payload.txt").unlink()
        os.link(outside, target / "assets" / "payload.txt")
        (target / "memories" / "preserve.txt").write_text("preserve\n", encoding="utf-8")
        (self.stage_root / "assets" / "payload.txt").write_text("new\n", encoding="utf-8")
        with mock.patch(
            "hermes_bootstrap.distributions._require_unlinked_managed_regular",
            wraps=distributions._require_unlinked_managed_regular,
        ) as require_unlinked:
            apply_profile_distribution(self.source("rick"), self.data_root, RecordingTransaction())

        self.assertEqual((target / "assets" / "payload.txt").read_text(encoding="utf-8"), "new\n")
        self.assertEqual(outside.read_text(encoding="utf-8"), "old\n")
        self.assertEqual((target / "memories" / "preserve.txt").read_text(encoding="utf-8"), "preserve\n")
        self.assertNotIn(mock.call(target / "memories"), require_unlinked.call_args_list)

    def test_profile_update_removes_stale_owned_paths_and_then_is_a_noop(self) -> None:
        (self.stage_root / "old.txt").write_text("old\n", encoding="utf-8")
        self.write_profile_manifest("rick", ["old.txt"])
        apply_profile_distribution(self.source("rick"), self.data_root, RecordingTransaction())
        target = self.data_root / "profiles" / "rick"
        (self.stage_root / "old.txt").unlink()
        (self.stage_root / "config.yaml").write_text("new\n", encoding="utf-8")
        self.write_profile_manifest("rick", ["config.yaml"])
        tx = StrictRecordingTransaction()

        changed = apply_profile_distribution(self.source("rick"), self.data_root, tx)

        self.assertFalse((target / "old.txt").exists())
        self.assertIn(target / "old.txt", changed.changed_paths)
        with mock.patch("hermes_bootstrap.distributions.profile_distribution.install_distribution") as install:
            self.assertEqual(apply_profile_distribution(self.source("rick"), self.data_root, StrictRecordingTransaction()), ChangeSet(()))
        install.assert_not_called()

    def test_profile_parent_to_child_transition_removes_parent_before_force_install(self) -> None:
        (self.stage_root / "docs").mkdir()
        (self.stage_root / "docs" / "obsolete.txt").write_text("old\n", encoding="utf-8")
        self.write_profile_manifest("rick", ["docs"])
        apply_profile_distribution(self.source("rick"), self.data_root, RecordingTransaction())
        target = self.data_root / "profiles" / "rick"
        shutil.rmtree(self.stage_root / "docs")
        (self.stage_root / "docs").mkdir()
        (self.stage_root / "docs" / "guide.md").write_text("new\n", encoding="utf-8")
        self.write_profile_manifest("rick", ["docs/guide.md"])
        tx = StrictRecordingTransaction()

        changed = apply_profile_distribution(self.source("rick"), self.data_root, tx)

        self.assertEqual((target / "docs" / "guide.md").read_text(encoding="utf-8"), "new\n")
        self.assertFalse((target / "docs" / "obsolete.txt").exists())
        self.assertIn(target / "docs", changed.changed_paths)
        self.assertEqual(tx.snapshots.count(target / "docs"), 1)

    def test_profile_child_covered_by_new_parent_is_not_removed_before_force_install(self) -> None:
        (self.stage_root / "docs").mkdir()
        (self.stage_root / "docs" / "old.txt").write_text("old\n", encoding="utf-8")
        self.write_profile_manifest("rick", ["docs/old.txt"])
        apply_profile_distribution(self.source("rick"), self.data_root, RecordingTransaction())
        target = self.data_root / "profiles" / "rick"
        (self.stage_root / "docs" / "guide.md").write_text("new\n", encoding="utf-8")
        self.write_profile_manifest("rick", ["docs"])

        with mock.patch("hermes_bootstrap.distributions.profile_distribution.install_distribution", side_effect=RuntimeError("stop")):
            self.assert_apply_error(lambda: apply_profile_distribution(self.source("rick"), self.data_root, RecordingTransaction()))

        self.assertEqual((target / "docs" / "old.txt").read_text(encoding="utf-8"), "old\n")

    def test_invalid_prior_profile_manifest_cannot_authorize_stale_deletion(self) -> None:
        target = self.data_root / "profiles" / "rick"
        target.mkdir(parents=True)
        (target / "old.txt").write_text("keep\n", encoding="utf-8")
        (target / "distribution.yaml").write_text(
            "name: rick\nversion: 0.1.0\nhermes_requires: '>=0.18.2'\ndistribution_owned:\n  - old.txt\n  - ../outside\n",
            encoding="utf-8",
        )
        (self.stage_root / "config.yaml").write_text("new\n", encoding="utf-8")
        self.write_profile_manifest("rick", ["config.yaml"])

        apply_profile_distribution(self.source("rick"), self.data_root, RecordingTransaction())

        self.assertEqual((target / "old.txt").read_text(encoding="utf-8"), "keep\n")

    def test_profile_rejects_whitespace_raw_identity_fields_before_writes(self) -> None:
        (self.stage_root / "config.yaml").write_text("config\n", encoding="utf-8")
        for overrides in ({"version": " 0.1.0"}, {"name": " rick"}, {"hermes_requires": " >=0.18.2"}):
            with self.subTest(overrides=overrides):
                self.write_profile_manifest("rick", ["config.yaml"], **overrides)
                self.assert_apply_error(lambda: apply_profile_distribution(self.source("rick"), self.data_root, RecordingTransaction()))
                self.assertFalse((self.data_root / "profiles" / "rick").exists())

    def test_profile_restores_home_without_mutating_it_when_preflight_fails(self) -> None:
        (self.stage_root / "config.yaml").write_text("config\n", encoding="utf-8")
        self.write_profile_manifest("rick", ["config.yaml"])
        previous_home = os.environ.get("HERMES_HOME")
        os.environ["HERMES_HOME"] = "preflight-home-marker"
        self.addCleanup(self.restore_environment, "HERMES_HOME", previous_home)

        with mock.patch("hermes_bootstrap.distributions._read_profile_manifest", side_effect=RuntimeError("early-secret-marker")):
            with self.assertRaises(ApplyError) as caught:
                apply_profile_distribution(self.source("rick"), self.data_root, RecordingTransaction())

        self.assertEqual(os.environ["HERMES_HOME"], "preflight-home-marker")
        self.assert_exception_hides_markers(caught.exception, "early-secret-marker", "preflight-home-marker", str(self.stage_root))

    def test_root_mutations_fsync_parents_and_hide_cleanup_failures(self) -> None:
        (self.stage_root / "config.yaml").write_text("config\n", encoding="utf-8")
        self.write_root_manifest(["config.yaml"])
        original_open = os.open
        original_fsync = os.fsync
        descriptor_paths: dict[int, Path] = {}
        synchronized: set[Path] = set()

        def record_open(path: object, *args: object, **kwargs: object) -> int:
            descriptor = original_open(path, *args, **kwargs)
            descriptor_paths[descriptor] = Path(path)
            return descriptor

        def record_fsync(descriptor: int) -> None:
            if descriptor in descriptor_paths:
                synchronized.add(descriptor_paths[descriptor])
            original_fsync(descriptor)

        with mock.patch("hermes_bootstrap.distributions.os.open", side_effect=record_open):
            with mock.patch("hermes_bootstrap.distributions.os.fsync", side_effect=record_fsync):
                apply_root_distribution(self.source("default", root=True), self.data_root, RecordingTransaction())

        self.assertIn(self.data_root, synchronized)
        self.assertIn(self.data_root / ".bootstrap", synchronized)

        self.data_root = self.root / "close-failure-data"
        self.data_root.mkdir()
        descriptors_to_fail: set[int] = set()

        def record_failure_open(path: object, *args: object, **kwargs: object) -> int:
            descriptor = original_open(path, *args, **kwargs)
            if Path(path) == self.data_root:
                descriptors_to_fail.add(descriptor)
            return descriptor

        original_close = os.close

        def fail_parent_close(descriptor: int) -> None:
            original_close(descriptor)
            if descriptor in descriptors_to_fail:
                raise OSError("close-secret-marker")

        with mock.patch("hermes_bootstrap.distributions.os.open", side_effect=record_failure_open):
            with mock.patch("hermes_bootstrap.distributions.os.close", side_effect=fail_parent_close):
                with self.assertRaises(ApplyError) as caught:
                    apply_root_distribution(self.source("default", root=True), self.data_root, RecordingTransaction())

        self.assertEqual((self.data_root / "config.yaml").read_text(encoding="utf-8"), "config\n")
        self.assert_exception_hides_markers(caught.exception, "close-secret-marker", str(self.stage_root))

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

        self.assertEqual(tx.snapshots, [self.data_root / "profiles"])
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

    def root_state(self, owned: list[str]) -> str:
        return json.dumps(
            {
                "source": "https://github.com/rurusasu/hermes-home.git",
                "ref": "main",
                "commit": "b" * 40,
                "version": "0.0.9",
                "distribution_owned": owned,
            }
        )

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
