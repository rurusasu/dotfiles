from __future__ import annotations

import io
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


BOOTSTRAP_ROOT = Path(__file__).resolve().parents[3] / "scripts" / "python"
sys.path.insert(0, str(BOOTSTRAP_ROOT))

from hermes_bootstrap.errors import (
    ApplyError,
    CredentialError,
    InputError,
    RepositoryError,
    ValidationError,
)
from hermes_bootstrap.models import BootstrapManifest, DistributionSource
from hermes_bootstrap.profile_sync import (
    ProfileDiff,
    ProfileSyncReport,
    ProfileSyncResult,
)


class CliTests(unittest.TestCase):
    def invoke(self, argv: list[str]) -> tuple[int, str, str]:
        from hermes_bootstrap import cli

        output = io.StringIO()
        errors = io.StringIO()
        code = cli.main(argv, stdin=io.StringIO(), stdout=output, stderr=errors, environ={})
        return code, output.getvalue(), errors.getvalue()

    def test_typed_errors_map_to_fixed_exit_codes_and_preserve_safe_messages(self) -> None:
        from hermes_bootstrap import cli

        for error, expected in (
            (InputError("bad"), 2), (CredentialError("bad"), 3), (RepositoryError("bad"), 4),
            (ApplyError("bad"), 6),
            (ValidationError("bad"), 8),
        ):
            with self.subTest(error=type(error).__name__), mock.patch.object(cli.app, "validate", side_effect=error):
                code, stdout, stderr = self.invoke(["validate"])
                self.assertEqual(code, expected)
                self.assertEqual(stdout, "")
                self.assertEqual(stderr, "bad\n")

    def test_debug_output_never_exposes_stdin_or_an_upstream_exception(self) -> None:
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
            output = io.StringIO()
            errors = io.StringIO()
            with (
                mock.patch.object(cli.app, "load_manifest", return_value=manifest),
                mock.patch.object(cli.app, "read_secret_payload", return_value=mock.Mock(github_token=token)),
                mock.patch.object(cli.app, "stage_distribution", side_effect=RuntimeError(token)),
            ):
                code = cli.main(
                    ["apply", "--manifest", "/manifest.yaml"],
                    stdin=io.StringIO(token),
                    stdout=output,
                    stderr=errors,
                    environ={"HERMES_BOOTSTRAP_DEBUG": "1", "GH_TOKEN": token},
                )

        self.assertEqual(code, 6)
        self.assertEqual(output.getvalue(), "")
        self.assertIn("ApplyError: bootstrap apply failed", errors.getvalue())
        self.assertNotIn(token, errors.getvalue())
        self.assertNotIn("RuntimeError", errors.getvalue())

    def test_output_broken_pipe_preserves_the_failure_exit_code(self) -> None:
        from hermes_bootstrap import cli

        failed = ProfileSyncResult(
            name="alpha",
            status="failed",
            commit=None,
            diff=ProfileDiff(),
            category="repository",
            message="profile synchronization failed",
        )
        report = ProfileSyncReport(False, (failed,), 4)
        output = io.StringIO()
        errors = io.StringIO()
        with (
            mock.patch.object(cli.app, "sync_profiles", return_value=report),
            mock.patch.object(output, "write", side_effect=BrokenPipeError),
        ):
            code = cli.main(
                ["sync-profiles"],
                stdin=io.StringIO(),
                stdout=output,
                stderr=errors,
                environ={},
            )

        self.assertEqual(code, 4)
        self.assertEqual(errors.getvalue(), "")
