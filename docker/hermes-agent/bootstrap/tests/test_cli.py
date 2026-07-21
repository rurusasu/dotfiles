from __future__ import annotations

import io
import json
import sys
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

    def test_stdout_broken_pipe_is_a_silent_success(self) -> None:
        from hermes_bootstrap import cli

        class BrokenOutput(io.StringIO):
            def write(self, _value: str) -> int:
                raise BrokenPipeError

        with mock.patch.object(cli.app, "validate", return_value={"status": "valid", "profiles": [], "repositories": []}):
            code = cli.main(["validate"], stdin=io.StringIO(), stdout=BrokenOutput(), stderr=io.StringIO(), environ={})
        self.assertEqual(code, 0)
