"""Actual fixture consumers keep full cleanup predicates without raw diagnostics."""

from __future__ import annotations

import tempfile
import unittest
from dataclasses import replace
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

from integration import test_bootstrap_flow as bootstrap_flow

SECRET_PATH = "secret-filename-token-content"
SECRET_BYTES = b"secret-payload-token-content"
ENTRY = bootstrap_flow.TreeEntry(
    "file", 0o600, 7, 11, 1, len(SECRET_BYTES), SECRET_BYTES
)


class CleanupFailureDisplayTests(unittest.TestCase):
    def _case(self, root: Path, before: dict, after: dict):
        case = bootstrap_flow.BootstrapFlowTests("runTest")
        case.data_root = root
        case.profile_tmpdir = root / "scratch"
        case.profile_tmpdir_before = before
        snapshots = []

        def snapshot(path, *, include_root):
            self.assertEqual(path, case.profile_tmpdir)
            self.assertFalse(include_root)
            snapshots.append("snapshot")
            return after

        case._snapshot_tree = snapshot
        return case, snapshots

    def test_empty_leaks_and_equal_private_snapshots_pass_once(self) -> None:
        # A false-positive cleanup failure must not reject an unchanged snapshot.
        with tempfile.TemporaryDirectory() as directory:
            before = {SECRET_PATH: ENTRY}
            case, snapshots = self._case(Path(directory), before, dict(before))
            case._assert_no_temporary_resources()
        self.assertEqual(snapshots, ["snapshot"])

    def test_unequal_same_count_snapshots_fail_without_values(self) -> None:
        # Count-only comparison misses all these full TreeEntry/path differences.
        changes = (
            ("bytes", SECRET_PATH, replace(ENTRY, payload=b"changed-secret-bytes")),
            ("mode", SECRET_PATH, replace(ENTRY, mode=0o640)),
            ("device", SECRET_PATH, replace(ENTRY, device=8)),
            ("inode", SECRET_PATH, replace(ENTRY, inode=12)),
            ("links", SECRET_PATH, replace(ENTRY, links=2)),
            ("size", SECRET_PATH, replace(ENTRY, size=999)),
            ("kind", SECRET_PATH, replace(ENTRY, kind="directory")),
            ("path", SECRET_PATH + "-changed", ENTRY),
        )
        for field, path, entry in changes:
            with self.subTest(field=field), tempfile.TemporaryDirectory() as directory:
                case, snapshots = self._case(
                    Path(directory), {SECRET_PATH: ENTRY}, {path: entry}
                )
                with self.assertRaises(AssertionError) as raised:
                    case._assert_no_temporary_resources()
                self.assertEqual(
                    str(raised.exception),
                    "False is not true : profile scratch cleanup mismatch (details redacted)",
                )
                self.assertEqual(snapshots, ["snapshot"])

    def test_real_leak_failure_hides_paths_and_precedes_snapshot(self) -> None:
        # Restoring raw sorted(leaks) exposes this private sentinel filename.
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / (".hermes-profile-sync-" + SECRET_PATH)).mkdir()
            case, snapshots = self._case(root, {}, {})
            with self.assertRaises(AssertionError) as raised:
                case._assert_no_temporary_resources()
            self.assertEqual(
                str(raised.exception),
                "True is not false : temporary resource leak (details redacted)",
            )
            self.assertEqual(snapshots, [])

    def test_snapshot_failure_preserves_finally_and_registered_cleanup_order(
        self,
    ) -> None:
        # Dropping finally or registered cleanups strands fixture child/resources.
        with tempfile.TemporaryDirectory() as directory:
            case, events = self._case(Path(directory), {SECRET_PATH: ENTRY}, {})
            case.setUp = lambda: None
            case.runTest = lambda: events.append("test")
            case.child_process_offset = 0
            child = SimpleNamespace(poll=lambda: events.append("child-check") or 0)
            case.addCleanup(events.append, "registered-first")
            case.addCleanup(events.append, "registered-second")
            result = unittest.TestResult()
            children = [child]
            with (
                mock.patch.object(bootstrap_flow, "_CHILD_PROCESSES", children),
                mock.patch.object(
                    bootstrap_flow.os, "waitpid", side_effect=ChildProcessError
                ),
            ):
                case.run(result)
        self.assertEqual(result.testsRun, 1)
        self.assertEqual(len(result.failures), 1)
        self.assertEqual(result.errors, [])
        self.assertIn(
            "profile scratch cleanup mismatch (details redacted)", result.failures[0][1]
        )
        self.assertNotIn(SECRET_PATH, result.failures[0][1])
        self.assertNotIn("TreeEntry(", result.failures[0][1])
        self.assertEqual(
            events,
            [
                "test",
                "snapshot",
                "child-check",
                "registered-second",
                "registered-first",
            ],
        )
        self.assertEqual(children, [])

    def test_leak_failure_still_stops_live_child_and_runs_registered_cleanups(
        self,
    ) -> None:
        # The existing finally must stop live children even after the first failure.
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / ("stage-" + SECRET_PATH)).mkdir()
            case, events = self._case(root, {}, {})
            case.setUp = lambda: None
            case.runTest = lambda: events.append("test")
            case.child_process_offset = 0
            child = SimpleNamespace(pid=123, poll=lambda: events.append("child-check"))
            children = [child]
            case.addCleanup(events.append, "registered-first")
            case.addCleanup(events.append, "registered-second")
            result = unittest.TestResult()
            with (
                mock.patch.object(bootstrap_flow, "_CHILD_PROCESSES", children),
                mock.patch.object(
                    bootstrap_flow,
                    "_stop_process",
                    side_effect=lambda process: (
                        events.append("stop-child")
                        if process is child
                        else self.fail("wrong child stopped")
                    ),
                ),
            ):
                case.run(result)
        self.assertEqual(result.testsRun, 1)
        self.assertEqual(len(result.failures), 1)
        self.assertEqual(result.errors, [])
        # Preserve the existing finally's child-failure precedence as well as cleanup.
        self.assertIn("[123] != []", result.failures[0][1])
        self.assertNotIn(SECRET_PATH, result.failures[0][1])
        self.assertEqual(
            events,
            [
                "test",
                "child-check",
                "stop-child",
                "registered-second",
                "registered-first",
            ],
        )
        self.assertEqual(children, [])


if __name__ == "__main__":
    unittest.main()
