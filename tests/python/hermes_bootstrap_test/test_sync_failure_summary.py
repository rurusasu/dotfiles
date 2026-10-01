"""Redaction and noninterference contracts for test-only sync diagnostics."""

from __future__ import annotations

import copy
import io
import unittest
from contextlib import redirect_stderr, redirect_stdout

try:
    from sync_failure_summary import initial_sync_summary
except ModuleNotFoundError as error:
    if error.name != "sync_failure_summary":
        raise
    initial_sync_summary = None


SECRET = "secret-sentinel-/private/path/token-content"


class UntrustedString(str):
    def __str__(self) -> str:
        raise AssertionError("untrusted string was rendered")


class UntrustedDict(dict):
    def get(self, *_args: object) -> object:
        raise AssertionError("untrusted mapping was read")


class UntrustedInt(int):
    def __str__(self) -> str:
        raise AssertionError("untrusted exit code was rendered")


class SyncFailureSummaryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.assertIsNotNone(initial_sync_summary, "safe test-only summary is missing")

    def test_known_fields_explain_cleanup_failure_without_raw_content(self) -> None:
        summary = initial_sync_summary(4, {
            "status": "failed",
            "message": SECRET,
            "profiles": [{
                "name": "rick", "status": "failed", "category": "cleanup_failed",
                "message": SECRET, "paths": [SECRET], "commit": SECRET,
            }],
        })
        self.assertIn("exit=4 status=failed", summary)
        self.assertIn("rick=failed/cleanup_failed", summary)
        self.assertNotIn(SECRET, summary)
        self.assertNotIn("message", summary)
        self.assertNotIn("paths", summary)
        self.assertNotIn("commit", summary)

    def test_unknown_profile_and_values_are_never_rendered(self) -> None:
        summary = initial_sync_summary(SECRET, {
            "status": SECRET,
            "profiles": [
                {"name": SECRET, "status": "failed", "category": "cleanup_failed"},
                {"name": "rick", "status": SECRET, "category": SECRET},
            ],
        })
        self.assertIn("exit=REDACTED status=REDACTED", summary)
        self.assertIn("rick=REDACTED/REDACTED", summary)
        self.assertNotIn(SECRET, summary)

    def test_exact_builtin_types_reject_subclasses_without_rendering_them(self) -> None:
        for payload in (
            UntrustedDict(status="failed"),
            {"status": UntrustedString("failed"), "profiles": [UntrustedDict(name="rick")]},
            {"profiles": [{"name": UntrustedString("rick"), "status": "failed"}]},
            {UntrustedString("profiles"): [{"name": "rick", "status": "changed", "category": "published"}]},
            {7: SECRET, "profiles": [{"name": "rick", "status": "changed", "category": "published"}]},
        ):
            with self.subTest(payload_type=type(payload).__name__):
                summary = initial_sync_summary(True, payload)
                self.assertIn("exit=REDACTED", summary)
                self.assertIn("status=REDACTED", summary)
                self.assertIn("rick=REDACTED/REDACTED", summary)

    def test_malformed_containers_and_fields_are_redacted(self) -> None:
        for payload in (None, [], SECRET, {"profiles": ()}, {"profiles": [None]},
                        {"profiles": [{"name": "rick", "status": [], "category": {}}]}):
            with self.subTest(payload_type=type(payload).__name__):
                summary = initial_sync_summary(4, payload)
                self.assertIn("rick=REDACTED/REDACTED", summary)
                self.assertNotIn(SECRET, summary)

    def test_duplicate_known_profile_is_redacted_instead_of_choosing_one(self) -> None:
        summary = initial_sync_summary(4, {"profiles": [
            {"name": "rick", "status": "changed", "category": "published"},
            {"name": "rick", "status": "failed", "category": "cleanup_failed"},
        ]})
        self.assertIn("rick=REDACTED/REDACTED", summary)

    def test_unbounded_collections_and_strings_have_bounded_output(self) -> None:
        for payload in (
            {"profiles": [{"name": "rick"}] * 10000},
            {"status": SECRET * 10000, "profiles": [{"name": SECRET * 10000}]},
            {SECRET + str(index): SECRET for index in range(10000)},
        ):
            summary = initial_sync_summary(10**1000, payload)
            self.assertLess(len(summary), 1024)
            self.assertNotIn(SECRET, summary)
            self.assertNotIn("\n", summary)

    def test_success_summary_does_not_mutate_payload_or_write_streams(self) -> None:
        payload = {"status": "changed", "profiles": [
            {"name": "rick", "status": "changed", "category": "published", "message": SECRET},
            {"name": "hoffman", "status": "unchanged", "category": "unchanged"},
        ]}
        before = copy.deepcopy(payload)
        stdout, stderr = io.StringIO(), io.StringIO()
        with redirect_stdout(stdout), redirect_stderr(stderr):
            summary = initial_sync_summary(0, payload)
        self.assertIn("exit=0 status=changed", summary)
        self.assertIn("rick=changed/published", summary)
        self.assertIn("hoffman=unchanged/unchanged", summary)
        self.assertEqual(payload, before)
        self.assertEqual((stdout.getvalue(), stderr.getvalue()), ("", ""))

    def test_fixed_exit_status_and_category_values_only(self) -> None:
        for exit_code, expected in ((0, "0"), (4, "4"), (8, "8"), (-1, "REDACTED"),
                                    (9, "REDACTED"), (4.0, "REDACTED"), (True, "REDACTED"),
                                    (UntrustedInt(4), "REDACTED")):
            self.assertIn(f"exit={expected} ", initial_sync_summary(exit_code, {}))
        for category in ("cleanup_failed", "repository", "resource_limit", "push_race_exhausted"):
            summary = initial_sync_summary(4, {"profiles": [
                {"name": "rick", "status": "failed", "category": category},
            ]})
            self.assertIn(f"rick=failed/{category}", summary)

    def test_real_initial_assertion_preserves_failure_and_hides_raw_streams(self) -> None:
        from integration.test_profile_sync_flow import ProfileSyncFlowTests

        case = ProfileSyncFlowTests("test_one_race_retries_once_and_a_second_race_returns_exit_four")
        calls = []
        def failed_sync():
            calls.append("initial")
            if len(calls) != 1:
                raise AssertionError("failed initial sync reached later race operations")
            return 4, {"status": "failed", "profiles": [{
                "name": "rick", "status": "failed", "category": "cleanup_failed", "message": SECRET,
            }]}, SECRET, SECRET
        case._run_sync = failed_sync
        stdout, stderr = io.StringIO(), io.StringIO()
        with redirect_stdout(stdout), redirect_stderr(stderr), self.assertRaises(AssertionError) as raised:
            case.test_one_race_retries_once_and_a_second_race_returns_exit_four()
        self.assertIn("4 != 0", str(raised.exception))
        self.assertIn("rick=failed/cleanup_failed", str(raised.exception))
        self.assertNotIn(SECRET, str(raised.exception))
        self.assertEqual((stdout.getvalue(), stderr.getvalue()), ("", ""))
        self.assertEqual(calls, ["initial"])


if __name__ == "__main__":
    unittest.main()
