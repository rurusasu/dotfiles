from __future__ import annotations

import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


BOOTSTRAP_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BOOTSTRAP_ROOT))

from hermes_bootstrap.errors import (
    ApplyError,
    CredentialError,
    InputError,
    MigrationError,
    RepositoryError,
    RollbackError,
    ValidationError,
)
from hermes_bootstrap.models import BootstrapManifest, DistributionSource
from hermes_bootstrap.payload import SecretRedactor
from hermes_bootstrap.profile_sync import (
    ProfileDiff,
    ProfileSyncReport,
    ProfileSyncResult,
)


class CliTests(unittest.TestCase):
    def invoke(self, argv: list[str], *, stdin: str = "") -> tuple[int, str, str]:
        from hermes_bootstrap import cli

        output = io.StringIO()
        errors = io.StringIO()
        code = cli.main(argv, stdin=io.StringIO(stdin), stdout=output, stderr=errors, environ={})
        return code, output.getvalue(), errors.getvalue()

    def test_secret_plan_writes_exact_compact_json_line(self) -> None:
        from hermes_bootstrap import cli

        plan = {"schema_version": 1, "items": [{"key": "github"}]}
        with mock.patch.object(cli.app, "secret_plan", return_value=plan):
            code, stdout, stderr = self.invoke(["secret-plan", "--manifest", "/manifest.yaml"])

        self.assertEqual(code, 0)
        self.assertEqual(stdout, '{"items":[{"key":"github"}],"schema_version":1}\n')
        self.assertEqual(stderr, "")

    def test_apply_alone_receives_stdin_and_success_is_one_non_secret_json_line(self) -> None:
        from hermes_bootstrap import cli

        stream = io.StringIO("secret payload")
        output = io.StringIO()
        errors = io.StringIO()
        with mock.patch.object(cli.app, "apply", return_value={"status": "applied", "profiles": ["rick"]}) as apply:
            code = cli.main(["apply"], stdin=stream, stdout=output, stderr=errors, environ={})
        self.assertEqual(code, 0)
        self.assertEqual(output.getvalue(), '{"profiles":["rick"],"status":"applied"}\n')
        self.assertEqual(errors.getvalue(), "")
        self.assertIs(apply.call_args.args[1], stream)

    def test_sync_profiles_dry_run_writes_one_compact_report_json_line(self) -> None:
        from hermes_bootstrap import cli

        report = ProfileSyncReport(dry_run=True, profiles=(), exit_code=0)
        with mock.patch.object(
            cli.app, "sync_profiles", return_value=report
        ) as sync_profiles:
            code, stdout, stderr = self.invoke(["sync-profiles", "--dry-run"])

        self.assertEqual(code, 0)
        self.assertEqual(
            stdout,
            '{"command":"sync-profiles","dry_run":true,"profiles":[],"schema_version":1,"status":"unchanged"}\n',
        )
        self.assertEqual(json.loads(stdout)["command"], "sync-profiles")
        self.assertEqual(stderr, "")
        sync_profiles.assert_called_once_with(
            Path(cli.DEFAULT_MANIFEST), dry_run=True, environ={}
        )

    def test_sync_profiles_failed_report_stays_on_stdout_and_sets_exit_code(self) -> None:
        from hermes_bootstrap import cli

        failed = ProfileSyncResult(
            name="alpha",
            status="failed",
            commit=None,
            snapshot="",
            diff=ProfileDiff(),
            category="repository",
            message="profile synchronization failed",
        )
        report = ProfileSyncReport(
            dry_run=False,
            profiles=(failed,),
            exit_code=RepositoryError.exit_code,
        )
        with mock.patch.object(cli.app, "sync_profiles", return_value=report):
            code, stdout, stderr = self.invoke(
                ["sync-profiles", "--manifest", "/manifest.yaml"]
            )

        self.assertEqual(code, RepositoryError.exit_code)
        self.assertEqual(json.loads(stdout), report.as_dict())
        self.assertEqual(stdout.count("\n"), 1)
        self.assertEqual(stderr, "")

    def test_sync_profiles_invalid_arguments_are_code_two_and_stdin_is_never_read(self) -> None:
        from hermes_bootstrap import cli

        class ExplodingInput(io.StringIO):
            def read(self, *args: object, **kwargs: object) -> str:
                raise AssertionError("stdin must remain unread")

        report = ProfileSyncReport(dry_run=True, profiles=(), exit_code=0)
        with mock.patch.object(cli.app, "sync_profiles", return_value=report):
            invalid_errors = io.StringIO()
            code = cli.main(
                ["sync-profiles", "extra"],
                stdin=ExplodingInput(),
                stdout=io.StringIO(),
                stderr=invalid_errors,
                environ={},
            )
            self.assertEqual(code, InputError.exit_code)
            self.assertEqual(
                invalid_errors.getvalue(), "invalid command arguments\n"
            )

            code = cli.main(
                ["sync-profiles", "--dry-run"],
                stdin=ExplodingInput(),
                stdout=io.StringIO(),
                stderr=io.StringIO(),
                environ={},
            )
            self.assertEqual(code, 0)

    def test_typed_errors_map_to_fixed_exit_codes_and_redact_messages(self) -> None:
        from hermes_bootstrap import cli

        for error, expected in (
            (InputError("bad"), 2), (CredentialError("bad"), 3), (RepositoryError("bad"), 4),
            (MigrationError("bad"), 5), (ApplyError("bad"), 6), (RollbackError("bad"), 7),
            (ValidationError("bad"), 8),
        ):
            with self.subTest(error=type(error).__name__), mock.patch.object(cli.app, "validate", side_effect=error):
                code, stdout, stderr = self.invoke(["validate"])
                self.assertEqual(code, expected)
                self.assertEqual(stdout, "")
                self.assertEqual(stderr, "bad\n")

    def test_unexpected_error_is_apply_code_and_never_leaks_secret_or_traceback_by_default(self) -> None:
        from hermes_bootstrap import cli

        with mock.patch.object(cli.app, "validate", side_effect=RuntimeError("token-needle")):
            code, stdout, stderr = self.invoke(["validate"])
        self.assertEqual(code, 6)
        self.assertEqual(stdout, "")
        self.assertEqual(stderr, "bootstrap command failed\n")
        self.assertNotIn("token-needle", stderr)

    def test_rejects_extra_arguments_and_never_reads_stdin_for_non_apply_commands(self) -> None:
        from hermes_bootstrap import cli

        class ExplodingInput(io.StringIO):
            def read(self, *args: object, **kwargs: object) -> str:
                raise AssertionError("stdin must remain unread")

        with mock.patch.object(cli.app, "validate", return_value={"status": "valid", "profiles": [], "repositories": []}):
            invalid_errors = io.StringIO()
            code = cli.main(["validate", "extra"], stdin=ExplodingInput(), stdout=io.StringIO(), stderr=invalid_errors, environ={})
            self.assertEqual(code, 2)
            self.assertEqual(invalid_errors.getvalue(), "invalid command arguments\n")
            code = cli.main(["validate"], stdin=ExplodingInput(), stdout=io.StringIO(), stderr=io.StringIO(), environ={})
            self.assertEqual(code, 0)

    def test_debug_traceback_uses_the_sanitized_error_boundary(self) -> None:
        from hermes_bootstrap import cli

        errors = io.StringIO()
        with mock.patch.object(cli.app, "validate", side_effect=ValidationError("layout invalid")):
            code = cli.main(["validate"], stdin=io.StringIO(), stdout=io.StringIO(), stderr=errors, environ={"HERMES_BOOTSTRAP_DEBUG": "1"})
        self.assertEqual(code, 8)
        self.assertIn("layout invalid", errors.getvalue())
        self.assertIn("ValidationError", errors.getvalue())

    def test_apply_debug_traceback_frames_never_retain_stdin_token(self) -> None:
        from hermes_bootstrap import cli

        token = "cli-debug-token-marker"
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "data"
            root.mkdir()
            manifest = BootstrapManifest(
                1,
                root,
                (),
                DistributionSource(
                    "default", "https://github.com/example/root.git", "main", root,
                    "root-distribution.yaml",
                ),
                (),
                (),
            )
            inspected: list[str] = []

            def inspect_traceback(_kind: object, _error: object, traceback: object) -> list[str]:
                while traceback is not None:
                    frame = traceback.tb_frame
                    if frame.f_code.co_filename.endswith(("hermes_bootstrap/app.py", "hermes_bootstrap/cli.py")):
                        inspected.append(frame.f_code.co_name)
                        for value in frame.f_locals.values():
                            self.assertNotIn(token, repr(value))
                        self.assertTrue(
                            set(frame.f_locals).isdisjoint(
                                {"secrets", "auth", "dashboard", "environment", "token"}
                            )
                        )
                    traceback = traceback.tb_next
                return ["sanitized traceback\n"]

            with (
                mock.patch.object(cli.app, "load_manifest", return_value=manifest),
                mock.patch.object(cli.app.Transaction, "recover_if_needed"),
                mock.patch.object(cli.app, "read_secret_payload", return_value=mock.Mock(github_token=token, redactor=SecretRedactor((token,)))),
                mock.patch.object(cli.app, "_validate_remote_credentials", side_effect=RuntimeError(token)),
                mock.patch.object(cli.traceback, "format_exception", side_effect=inspect_traceback),
            ):
                errors = io.StringIO()
                code = cli.main(
                    ["apply", "--manifest", "/manifest.yaml"],
                    stdin=io.StringIO(token),
                    stdout=io.StringIO(),
                    stderr=errors,
                    environ={"HERMES_BOOTSTRAP_DEBUG": "1", "GH_TOKEN": token},
                )

        self.assertEqual(code, 6)
        self.assertEqual(inspected, ["main"])
        self.assertNotIn(token, errors.getvalue())

    def test_stdout_broken_pipe_is_a_silent_success(self) -> None:
        from hermes_bootstrap import cli

        class BrokenOutput(io.StringIO):
            def write(self, _value: str) -> int:
                raise BrokenPipeError

        with mock.patch.object(cli.app, "validate", return_value={"status": "valid", "profiles": [], "repositories": []}):
            code = cli.main(["validate"], stdin=io.StringIO(), stdout=BrokenOutput(), stderr=io.StringIO(), environ={})
        self.assertEqual(code, 0)

    def test_sync_profiles_broken_pipe_keeps_the_existing_silent_success_contract(self) -> None:
        from hermes_bootstrap import cli

        class BrokenOutput(io.StringIO):
            def write(self, _value: str) -> int:
                raise BrokenPipeError

        failed = ProfileSyncResult(
            name="alpha",
            status="failed",
            commit=None,
            snapshot="",
            diff=ProfileDiff(),
            category="repository",
            message="profile synchronization failed",
        )
        report = ProfileSyncReport(
            dry_run=False,
            profiles=(failed,),
            exit_code=RepositoryError.exit_code,
        )
        with mock.patch.object(cli.app, "sync_profiles", return_value=report):
            code = cli.main(
                ["sync-profiles"],
                stdin=io.StringIO(),
                stdout=BrokenOutput(),
                stderr=io.StringIO(),
                environ={},
            )
        self.assertEqual(code, 0)
