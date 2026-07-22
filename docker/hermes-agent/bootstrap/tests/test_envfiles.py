from __future__ import annotations

import os
import stat
import sys
import tempfile
import unittest
from pathlib import Path
from types import MappingProxyType
from types import FrameType, TracebackType
from unittest import mock


BOOTSTRAP_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BOOTSTRAP_ROOT))

from hermes_bootstrap.errors import ApplyError, InputError
from hermes_bootstrap.payload import DashboardSecret, SecretBundle, SecretRedactor, SlackSecret
from hermes_bootstrap.envfiles import (
    API_SERVER_KEYS,
    DASHBOARD_KEYS,
    GITHUB_KEYS,
    SLACK_KEYS,
    build_dashboard_environment,
    build_profile_environment,
    merge_env_file,
    read_environment_values,
)


def secret_bundle() -> SecretBundle:
    return SecretBundle(
        github_token="github-secret-value",
        dashboard=DashboardSecret(username="dashboard-user", password="dashboard-password"),
        slack_by_profile=MappingProxyType(
            {
                "default": SlackSecret("default-bot", "default-app", "default-users"),
                "rick": SlackSecret("rick-bot", "rick-app", "rick-users"),
                "hoffman": SlackSecret("hoffman-bot", "hoffman-app", "hoffman-users"),
            }
        ),
        redactor=SecretRedactor(("github-secret-value", "dashboard-user", "dashboard-password")),
    )


def capture_atomic_write_error(path: Path) -> BaseException:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("KEEP=original\n", encoding="utf-8")
    with mock.patch("hermes_bootstrap.envfiles.os.replace", side_effect=OSError("replace failed")):
        try:
            merge_env_file(path, {"GH_TOKEN": "atomic-write-secret-marker"}, frozenset())
        except ApplyError as error:
            return error
    raise AssertionError("expected atomic update to fail")


def capture_dashboard_build_error() -> BaseException:
    bundle = SecretBundle(
        github_token="build-github-marker",
        dashboard=DashboardSecret("build-user-marker", "build-password-marker"),
        slack_by_profile=MappingProxyType(
            {"default": SlackSecret("build-bot-marker", "build-app-marker", "build-users-marker")}
        ),
        redactor=SecretRedactor(("build-password-marker",)),
    )
    try:
        with mock.patch(
            "hermes_bootstrap.envfiles.hash_password",
            side_effect=RuntimeError("hash failed"),
        ):
            build_dashboard_environment(bundle)
    except ApplyError as error:
        del bundle
        return error
    raise AssertionError("expected dashboard build to fail")


class EnvFileTests(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.path = self.root / "profiles" / "rick" / ".env"

    def test_managed_key_sets_are_exact(self) -> None:
        self.assertEqual(
            GITHUB_KEYS,
            frozenset({"GITHUB_PERSONAL_ACCESS_TOKEN", "GH_TOKEN", "GITHUB_TOKEN"}),
        )
        self.assertEqual(
            DASHBOARD_KEYS,
            frozenset(
                {
                    "HERMES_DASHBOARD_BASIC_AUTH_USERNAME",
                    "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH",
                    "HERMES_DASHBOARD_BASIC_AUTH_SECRET",
                }
            ),
        )
        self.assertEqual(
            SLACK_KEYS,
            frozenset({"SLACK_BOT_TOKEN", "SLACK_APP_TOKEN", "SLACK_ALLOWED_USERS"}),
        )
        self.assertEqual(API_SERVER_KEYS, frozenset({"API_SERVER_KEY"}))

    def test_absent_file_creates_parents_and_canonical_managed_block(self) -> None:
        changed = merge_env_file(
            self.path,
            {"GH_TOKEN": "token=value", "SLACK_APP_TOKEN": "app"},
            frozenset(),
        )

        self.assertTrue(changed)
        self.assertEqual(
            self.path.read_bytes(),
            b"GH_TOKEN=token=value\nSLACK_APP_TOKEN=app\n",
        )
        self.assertEqual(stat.S_IMODE(self.path.stat().st_mode), 0o600)

    def test_preserves_unmanaged_lines_and_removes_direct_and_export_managed_duplicates(self) -> None:
        self.path.parent.mkdir(parents=True)
        self.path.write_bytes(
            b"# preserved comment\r\n"
            b"KEEP=one=two\r\n"
            b" export GH_TOKEN = old-one\r\n"
            b"GH_TOKEN=old-two\r\n"
            b" export OLD_SLACK = stale\r\n"
            b"HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=old-plaintext\r\n"
            b"# another comment\r\n"
        )

        changed = merge_env_file(
            self.path,
            {"GH_TOKEN": "new=token"},
            frozenset({"OLD_SLACK"}),
        )

        self.assertTrue(changed)
        self.assertEqual(
            self.path.read_bytes(),
            b"# preserved comment\n"
            b"KEEP=one=two\n"
            b"# another comment\n"
            b"\n"
            b"GH_TOKEN=new=token\n",
        )

    def test_missing_final_newline_is_normalized_and_empty_managed_block_is_allowed(self) -> None:
        self.path.parent.mkdir(parents=True)
        self.path.write_bytes(b"# preserve without newline")

        changed = merge_env_file(self.path, {}, frozenset())

        self.assertTrue(changed)
        self.assertEqual(self.path.read_bytes(), b"# preserve without newline\n")

    def test_managed_block_preserves_mapping_insertion_order(self) -> None:
        changed = merge_env_file(
            self.path,
            {"Z_LAST": "first", "A_FIRST": "second"},
            frozenset(),
        )

        self.assertTrue(changed)
        self.assertEqual(self.path.read_bytes(), b"Z_LAST=first\nA_FIRST=second\n")

    def test_invalid_key_or_value_fails_without_exposing_or_writing_secret(self) -> None:
        self.path.parent.mkdir(parents=True)
        self.path.write_text("KEEP=original\n", encoding="utf-8")
        for managed in (
            {"bad-key": "secret-marker"},
            {"VALID_KEY": "secret-marker\n"},
            {"VALID_KEY": "secret-marker\x00"},
        ):
            with self.subTest(managed=tuple(managed)):
                with self.assertRaises(InputError) as caught:
                    merge_env_file(self.path, managed, frozenset())
                self.assertNotIn("secret-marker", str(caught.exception))
                self.assertEqual(self.path.read_text(encoding="utf-8"), "KEEP=original\n")

    def test_idempotent_apply_preserves_inode_and_enforces_mode(self) -> None:
        self.path.parent.mkdir(parents=True)
        self.path.write_bytes(b"KEEP=yes\n\nGH_TOKEN=token\n")
        os.chmod(self.path, 0o644)
        inode = self.path.stat().st_ino

        changed = merge_env_file(self.path, {"GH_TOKEN": "token"}, frozenset())

        self.assertFalse(changed)
        self.assertEqual(self.path.stat().st_ino, inode)
        self.assertEqual(stat.S_IMODE(self.path.stat().st_mode), 0o600)

    def test_changed_content_replaces_file_atomically(self) -> None:
        self.path.parent.mkdir(parents=True)
        self.path.write_text("GH_TOKEN=old\n", encoding="utf-8")
        original_inode = self.path.stat().st_ino

        self.assertTrue(merge_env_file(self.path, {"GH_TOKEN": "new"}, frozenset()))

        self.assertNotEqual(self.path.stat().st_ino, original_inode)
        self.assertEqual(self.path.read_bytes(), b"GH_TOKEN=new\n")
        self.assertEqual(stat.S_IMODE(self.path.stat().st_mode), 0o600)

    def test_symlink_and_nonregular_targets_are_rejected_without_modifying_target(self) -> None:
        self.path.parent.mkdir(parents=True)
        original = self.root / "original.env"
        original.write_text("KEEP=original\n", encoding="utf-8")
        self.path.symlink_to(original)
        with self.assertRaises(ApplyError):
            merge_env_file(self.path, {"GH_TOKEN": "secret"}, frozenset())
        self.assertEqual(original.read_text(encoding="utf-8"), "KEEP=original\n")

        self.path.unlink()
        os.mkfifo(self.path)
        self.addCleanup(lambda: self.path.exists() and self.path.unlink())
        with self.assertRaises(ApplyError):
            merge_env_file(self.path, {"GH_TOKEN": "secret"}, frozenset())

    def test_replace_failure_keeps_original_and_cleans_up_temporary_files(self) -> None:
        self.path.parent.mkdir(parents=True)
        self.path.write_text("KEEP=original\n", encoding="utf-8")
        with mock.patch("hermes_bootstrap.envfiles.os.replace", side_effect=OSError("replace failed")):
            with self.assertRaises(ApplyError) as caught:
                merge_env_file(self.path, {"GH_TOKEN": "secret-marker"}, frozenset())

        self.assertNotIn("secret-marker", str(caught.exception))
        self.assertEqual(self.path.read_text(encoding="utf-8"), "KEEP=original\n")
        self.assertEqual(list(self.path.parent.glob(".env.*.tmp")), [])

    def test_atomic_write_cleanup_failure_preserves_primary_error_and_removes_temporary_file(self) -> None:
        self.path.parent.mkdir(parents=True)
        self.path.write_text("KEEP=original\n", encoding="utf-8")
        real_close = os.close

        def close_then_fail(descriptor: int) -> None:
            real_close(descriptor)
            raise OSError("close failed")

        with mock.patch("hermes_bootstrap.envfiles.os.fchmod", side_effect=OSError("chmod failed")):
            with mock.patch("hermes_bootstrap.envfiles.os.close", side_effect=close_then_fail) as close:
                with self.assertRaises(ApplyError) as caught:
                    merge_env_file(
                        self.path,
                        {"GH_TOKEN": "atomic-cleanup-secret-marker"},
                        frozenset(),
                    )

        self.assertEqual(str(caught.exception), "could not atomically update environment file")
        self.assertEqual(close.call_count, 1)
        self.assertIsNone(caught.exception.__cause__)
        self.assertIsNone(caught.exception.__context__)
        self.assert_exception_hides_markers(caught.exception, "atomic-cleanup-secret-marker")
        self.assertEqual(self.path.read_text(encoding="utf-8"), "KEEP=original\n")
        self.assertEqual(list(self.path.parent.glob(".env.*.tmp")), [])

    def test_parent_fsync_cleanup_failure_preserves_primary_error_without_secret_traceback(self) -> None:
        self.path.parent.mkdir(parents=True)
        parent_descriptor = 12345
        real_fsync = os.fsync
        real_open = os.open

        def open_parent_only(*args: object, **kwargs: object) -> int:
            if Path(args[0]) == self.path.parent:
                return parent_descriptor
            return real_open(*args, **kwargs)

        def fsync_parent_only(descriptor: int) -> None:
            if descriptor == parent_descriptor:
                raise OSError("parent fsync failed")
            real_fsync(descriptor)

        with mock.patch("hermes_bootstrap.envfiles.os.open", side_effect=open_parent_only):
            with mock.patch("hermes_bootstrap.envfiles.os.fsync", side_effect=fsync_parent_only):
                with mock.patch(
                    "hermes_bootstrap.envfiles.os.close", side_effect=OSError("close failed")
                ) as close:
                    with self.assertRaises(ApplyError) as caught:
                        merge_env_file(
                            self.path,
                            {"GH_TOKEN": "parent-fsync-secret-marker"},
                            frozenset(),
                        )

        self.assertEqual(str(caught.exception), "could not synchronize environment file directory")
        self.assertEqual(close.call_args_list, [mock.call(parent_descriptor)])
        self.assertIsNone(caught.exception.__cause__)
        self.assertIsNone(caught.exception.__context__)
        self.assert_exception_hides_markers(caught.exception, "parent-fsync-secret-marker")

    def test_parent_close_failure_is_sanitized_after_successful_fsync(self) -> None:
        self.path.parent.mkdir(parents=True)
        parent_descriptor = 12345
        real_fsync = os.fsync
        real_open = os.open

        def open_parent_only(*args: object, **kwargs: object) -> int:
            if Path(args[0]) == self.path.parent:
                return parent_descriptor
            return real_open(*args, **kwargs)

        def fsync_parent_only(descriptor: int) -> None:
            if descriptor != parent_descriptor:
                real_fsync(descriptor)

        with mock.patch("hermes_bootstrap.envfiles.os.open", side_effect=open_parent_only):
            with mock.patch("hermes_bootstrap.envfiles.os.fsync", side_effect=fsync_parent_only):
                with mock.patch(
                    "hermes_bootstrap.envfiles.os.close", side_effect=OSError("close failed")
                ) as close:
                    with self.assertRaises(ApplyError) as caught:
                        merge_env_file(
                            self.path,
                            {"GH_TOKEN": "parent-close-secret-marker"},
                            frozenset(),
                        )

        self.assertEqual(str(caught.exception), "could not synchronize environment file directory")
        self.assertEqual(close.call_args_list, [mock.call(parent_descriptor)])
        self.assertIsNone(caught.exception.__cause__)
        self.assertIsNone(caught.exception.__context__)
        self.assert_exception_hides_markers(caught.exception, "parent-close-secret-marker")

    def test_build_and_atomic_write_failures_discard_secret_tracebacks(self) -> None:
        atomic_error = capture_atomic_write_error(self.path)
        dashboard_error = capture_dashboard_build_error()

        for error, markers in (
            (atomic_error, ("atomic-write-secret-marker",)),
            (
                dashboard_error,
                (
                    "build-github-marker",
                    "build-user-marker",
                    "build-password-marker",
                    "build-bot-marker",
                    "build-app-marker",
                    "build-users-marker",
                ),
            ),
        ):
            with self.subTest(error=type(error).__name__):
                self.assertIsNone(error.__cause__)
                self.assertIsNone(error.__context__)
                self.assert_exception_hides_markers(error, *markers)

    def assert_exception_hides_markers(self, error: BaseException, *markers: str) -> None:
        pending: list[object] = [error]
        visited: set[int] = set()
        while pending:
            value = pending.pop()
            identifier = id(value)
            if identifier in visited:
                continue
            visited.add(identifier)

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
                pending.extend(value.f_locals.values())
            elif isinstance(value, MappingProxyType):
                pending.extend(value.values())
            elif isinstance(value, dict):
                pending.extend((*value.keys(), *value.values()))
            elif isinstance(value, (list, tuple, set, frozenset)):
                pending.extend(value)

    def test_dashboard_is_hashed_once_and_profile_environment_reuses_it_without_plaintext(self) -> None:
        secrets = secret_bundle()
        with mock.patch("hermes_bootstrap.envfiles.hash_password", return_value="hashed-password") as hash_password:
            with mock.patch(
                "hermes_bootstrap.envfiles.secrets.token_urlsafe",
                side_effect=("signing-secret", "api-server-key"),
            ) as token_urlsafe:
                dashboard = build_dashboard_environment(secrets)

        self.assertEqual(hash_password.call_args_list, [mock.call("dashboard-password")])
        self.assertEqual(token_urlsafe.call_args_list, [mock.call(48), mock.call(48)])
        self.assertIsInstance(dashboard, MappingProxyType)
        self.assertEqual(
            dashboard,
            {
                "HERMES_DASHBOARD_BASIC_AUTH_USERNAME": "dashboard-user",
                "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH": "hashed-password",
                "HERMES_DASHBOARD_BASIC_AUTH_SECRET": "signing-secret",
                "API_SERVER_KEY": "api-server-key",
            },
        )
        for secret in (
            "dashboard-user",
            "dashboard-password",
            "hashed-password",
            "signing-secret",
            "api-server-key",
        ):
            self.assertNotIn(secret, repr(dashboard))

        root_environment = build_profile_environment("default", secrets, dashboard)
        rick_environment = build_profile_environment("rick", secrets, dashboard)
        self.assertIsInstance(root_environment, MappingProxyType)
        self.assertEqual(root_environment["SLACK_BOT_TOKEN"], "default-bot")
        self.assertEqual(rick_environment["SLACK_BOT_TOKEN"], "rick-bot")
        for key in GITHUB_KEYS | DASHBOARD_KEYS | API_SERVER_KEYS:
            self.assertEqual(root_environment[key], rick_environment[key])
        for environment in (root_environment, rick_environment):
            for secret in (
                "github-secret-value",
                "dashboard-user",
                "dashboard-password",
                "hashed-password",
                "signing-secret",
                "default-bot",
                "default-app",
                "default-users",
                "rick-bot",
                "rick-app",
                "rick-users",
            ):
                self.assertNotIn(secret, repr(environment))
            self.assertNotIn("HERMES_DASHBOARD_BASIC_AUTH_PASSWORD", environment)
        with self.assertRaises(TypeError):
            root_environment["GH_TOKEN"] = "changed"

    def test_dashboard_reuses_matching_hash_and_strong_signing_secret(self) -> None:
        existing = MappingProxyType(
            {
                "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH": "existing-hash",
                "HERMES_DASHBOARD_BASIC_AUTH_SECRET": "existing-signing-secret-that-is-long-enough",
                "API_SERVER_KEY": "existing-independent-api-key-that-is-long-enough",
            }
        )

        with mock.patch("hermes_bootstrap.envfiles._verify_password", return_value=True) as verify_password:
            with mock.patch("hermes_bootstrap.envfiles.hash_password") as hash_password:
                with mock.patch("hermes_bootstrap.envfiles.secrets.token_urlsafe") as token_urlsafe:
                    dashboard = build_dashboard_environment(secret_bundle(), existing)

        verify_password.assert_called_once_with("dashboard-password", "existing-hash")
        hash_password.assert_not_called()
        token_urlsafe.assert_not_called()
        self.assertEqual(
            dashboard["HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH"],
            "existing-hash",
        )
        self.assertEqual(
            dashboard["HERMES_DASHBOARD_BASIC_AUTH_SECRET"],
            "existing-signing-secret-that-is-long-enough",
        )
        self.assertEqual(
            dashboard["API_SERVER_KEY"],
            "existing-independent-api-key-that-is-long-enough",
        )

    def test_reads_only_unique_requested_values_from_a_regular_environment_file(self) -> None:
        self.path.parent.mkdir(parents=True)
        self.path.write_text(
            "KEEP=visible\n"
            "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH=existing-hash\n"
            "HERMES_DASHBOARD_BASIC_AUTH_SECRET=existing-secret\n",
            encoding="utf-8",
        )

        values = read_environment_values(self.path, DASHBOARD_KEYS | API_SERVER_KEYS)

        self.assertEqual(
            values,
            {
                "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH": "existing-hash",
                "HERMES_DASHBOARD_BASIC_AUTH_SECRET": "existing-secret",
            },
        )
        self.assertNotIn("existing-secret", repr(values))

    def test_profile_environment_rejects_unknown_profile_without_secret_error(self) -> None:
        secrets = secret_bundle()
        dashboard = MappingProxyType(
            {
                "HERMES_DASHBOARD_BASIC_AUTH_USERNAME": "dashboard-user",
                "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH": "hash",
                "HERMES_DASHBOARD_BASIC_AUTH_SECRET": "secret",
            }
        )

        with self.assertRaises(InputError) as caught:
            build_profile_environment("unknown", secrets, dashboard)

        self.assertNotIn("dashboard-password", str(caught.exception))


if __name__ == "__main__":
    unittest.main()
