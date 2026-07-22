from __future__ import annotations

import os
import stat
import sys
import tempfile
import unittest
from io import StringIO
from pathlib import Path
from types import MappingProxyType
from types import FrameType, TracebackType
from unittest import mock

from dotenv import dotenv_values


BOOTSTRAP_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BOOTSTRAP_ROOT))
API_KEY_BODY = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

import hermes_bootstrap.envfiles as envfiles_module
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
            b"GH_TOKEN='token=value'\nSLACK_APP_TOKEN='app'\n",
        )
        self.assertEqual(stat.S_IMODE(self.path.stat().st_mode), 0o600)

    def test_preserves_unmanaged_lines_and_removes_direct_and_export_managed_duplicates(self) -> None:
        self.path.parent.mkdir(parents=True)
        self.path.write_bytes(
            b"# preserved comment\r\n"
            b"KEEP=one=two\r\n"
            b" export GH_TOKEN = old-one\r\n"
            b"GH_TOKEN=old-two\r\n"
            b"export GH_TOKEN\r\n"
            b"GH_TOKEN malformed\r\n"
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
            b"GH_TOKEN='new=token'\n",
        )

    def test_missing_final_newline_is_normalized_and_empty_managed_block_is_allowed(self) -> None:
        self.path.parent.mkdir(parents=True)
        self.path.write_bytes(b"# preserve without newline")

        changed = merge_env_file(self.path, {}, frozenset())

        self.assertTrue(changed)
        self.assertEqual(self.path.read_bytes(), b"# preserve without newline\n")

    def test_replaces_an_entire_quoted_multiline_managed_assignment(self) -> None:
        self.path.parent.mkdir(parents=True)
        self.path.write_bytes(
            b"KEEP=before\n"
            b'GH_TOKEN="\n'
            b"old-secret-continuation\n"
            b'"\n'
            b"KEEP_AFTER=yes\n"
        )

        changed = merge_env_file(self.path, {"GH_TOKEN": "new-token"}, frozenset())

        self.assertTrue(changed)
        self.assertEqual(
            self.path.read_bytes(),
            b"KEEP=before\nKEEP_AFTER=yes\n\nGH_TOKEN='new-token'\n",
        )
        self.assertNotIn(b"old-secret-continuation", self.path.read_bytes())

    def test_removes_a_backslash_continuation_after_a_managed_assignment(self) -> None:
        self.path.parent.mkdir(parents=True)
        self.path.write_bytes(
            b"KEEP=before\n"
            b"GH_TOKEN=old-secret\\\n"
            b"LD_PRELOAD=/tmp/unintended\n"
            b"KEEP_AFTER=yes\n"
        )

        changed = merge_env_file(self.path, {"GH_TOKEN": "new-token"}, frozenset())

        self.assertTrue(changed)
        self.assertEqual(
            self.path.read_bytes(),
            b"KEEP=before\nKEEP_AFTER=yes\n\nGH_TOKEN='new-token'\n",
        )

    def test_managed_block_preserves_mapping_insertion_order(self) -> None:
        changed = merge_env_file(
            self.path,
            {"Z_LAST": "first", "A_FIRST": "second"},
            frozenset(),
        )

        self.assertTrue(changed)
        self.assertEqual(self.path.read_bytes(), b"Z_LAST='first'\nA_FIRST='second'\n")

    def test_managed_values_round_trip_without_comments_or_interpolation(self) -> None:
        value = "literal # comment $EXPANDED 'quote' \\ tail"

        changed = merge_env_file(self.path, {"GH_TOKEN": value}, frozenset())

        self.assertTrue(changed)
        rendered = self.path.read_text(encoding="utf-8")
        self.assertEqual(
            dotenv_values(stream=StringIO(rendered), interpolate=True)["GH_TOKEN"],
            value,
        )
        self.assertEqual(read_environment_values(self.path, GITHUB_KEYS)["GH_TOKEN"], value)

    def test_managed_values_reject_braced_interpolation_without_writing_it(self) -> None:
        value = "literal-${EXPANDED}-secret-marker"

        with self.assertRaises(InputError) as caught:
            merge_env_file(self.path, {"GH_TOKEN": value}, frozenset())

        self.assertFalse(self.path.exists())
        self.assertNotIn(value, str(caught.exception))

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
        self.path.write_bytes(b"KEEP=yes\n\nGH_TOKEN='token'\n")
        os.chmod(self.path, 0o644)
        inode = self.path.stat().st_ino

        changed = merge_env_file(self.path, {"GH_TOKEN": "token"}, frozenset())

        self.assertFalse(changed)
        self.assertEqual(self.path.stat().st_ino, inode)
        self.assertEqual(stat.S_IMODE(self.path.stat().st_mode), 0o600)

    def test_idempotent_apply_rejects_a_file_replaced_before_chmod(self) -> None:
        self.path.parent.mkdir(parents=True)
        self.path.write_text("GH_TOKEN='token'\n", encoding="utf-8")
        self.path.chmod(0o644)
        real_chmod = envfiles_module._chmod_private_at

        def replace_then_chmod(parent_descriptor: int, name: str, *arguments: object) -> None:
            self.path.unlink()
            self.path.write_text("GH_TOKEN='attacker'\n", encoding="utf-8")
            self.path.chmod(0o644)
            real_chmod(parent_descriptor, name, *arguments)

        with mock.patch.object(
            envfiles_module,
            "_chmod_private_at",
            side_effect=replace_then_chmod,
        ):
            with self.assertRaises(ApplyError):
                merge_env_file(self.path, {"GH_TOKEN": "token"}, frozenset())

        self.assertEqual(self.path.read_text(encoding="utf-8"), "GH_TOKEN='attacker'\n")
        self.assertEqual(stat.S_IMODE(self.path.stat().st_mode), 0o644)

    def test_changed_content_replaces_file_atomically(self) -> None:
        self.path.parent.mkdir(parents=True)
        self.path.write_text("GH_TOKEN=old\n", encoding="utf-8")
        original_inode = self.path.stat().st_ino

        self.assertTrue(merge_env_file(self.path, {"GH_TOKEN": "new"}, frozenset()))

        self.assertNotEqual(self.path.stat().st_ino, original_inode)
        self.assertEqual(self.path.read_bytes(), b"GH_TOKEN='new'\n")
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

    def test_hardlinked_target_is_rejected_without_reading_or_chmodding_the_external_file(self) -> None:
        self.path.parent.mkdir(parents=True)
        external = self.root / "external.env"
        external.write_bytes(b"KEEP=external-secret-marker\n")
        os.chmod(external, 0o644)
        os.link(external, self.path)

        with self.assertRaises(ApplyError) as caught:
            merge_env_file(self.path, {"GH_TOKEN": "token"}, frozenset())

        self.assertNotIn("external-secret-marker", str(caught.exception))
        self.assertEqual(external.read_bytes(), b"KEEP=external-secret-marker\n")
        self.assertEqual(stat.S_IMODE(external.stat().st_mode), 0o644)

    def test_swapped_parent_is_rejected_without_reading_or_updating_the_external_file(self) -> None:
        self.path.parent.mkdir(parents=True)
        self.path.write_text("GH_TOKEN=original\n", encoding="utf-8")
        held = self.root / "held-profile"
        outside = self.root / "outside-profile"
        outside.mkdir()
        outside_env = outside / ".env"
        outside_env.write_text("KEEP=external-secret-marker\n", encoding="utf-8")
        real_ensure_parent = envfiles_module._ensure_parent_directory

        def swap_parent(parent: Path) -> None:
            real_ensure_parent(parent)
            parent.rename(held)
            parent.symlink_to(outside, target_is_directory=True)

        with mock.patch.object(
            envfiles_module,
            "_ensure_parent_directory",
            side_effect=swap_parent,
        ):
            with self.assertRaises(ApplyError) as caught:
                merge_env_file(self.path, {"GH_TOKEN": "new-token"}, frozenset())

        self.assertNotIn("external-secret-marker", str(caught.exception))
        self.assertEqual(outside_env.read_text(encoding="utf-8"), "KEEP=external-secret-marker\n")

    def test_parent_swapped_after_open_is_rejected_before_any_environment_update(self) -> None:
        self.path.parent.mkdir(parents=True)
        self.path.write_text("GH_TOKEN=original\n", encoding="utf-8")
        held = self.root / "held-after-open"
        outside = self.root / "outside-after-open"
        outside.mkdir()
        outside_env = outside / ".env"
        outside_env.write_text("KEEP=external\n", encoding="utf-8")
        real_open_parent = envfiles_module._open_environment_parent

        def open_then_swap(parent: Path) -> int:
            descriptor = real_open_parent(parent)
            parent.rename(held)
            parent.symlink_to(outside, target_is_directory=True)
            return descriptor

        with mock.patch.object(
            envfiles_module,
            "_open_environment_parent",
            side_effect=open_then_swap,
        ):
            with self.assertRaises(ApplyError):
                merge_env_file(self.path, {"GH_TOKEN": "new-token"}, frozenset())

        self.assertEqual((held / ".env").read_text(encoding="utf-8"), "GH_TOKEN=original\n")
        self.assertEqual(outside_env.read_text(encoding="utf-8"), "KEEP=external\n")

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
        failed_regular_closes: list[int] = []

        def close_then_fail(descriptor: int) -> None:
            regular = stat.S_ISREG(os.fstat(descriptor).st_mode)
            real_close(descriptor)
            if regular:
                failed_regular_closes.append(descriptor)
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
        self.assertGreater(close.call_count, 1)
        self.assertEqual(len(failed_regular_closes), 2)
        self.assertIsNone(caught.exception.__cause__)
        self.assertIsNone(caught.exception.__context__)
        self.assert_exception_hides_markers(caught.exception, "atomic-cleanup-secret-marker")
        self.assertEqual(self.path.read_text(encoding="utf-8"), "KEEP=original\n")
        self.assertEqual(list(self.path.parent.glob(".env.*.tmp")), [])

    def test_parent_fsync_cleanup_failure_preserves_primary_error_without_secret_traceback(self) -> None:
        self.path.parent.mkdir(parents=True)
        parent_info = self.path.parent.stat()
        parent_identity = (parent_info.st_dev, parent_info.st_ino)
        real_fsync = os.fsync
        real_close = os.close
        failed_parent_closes: list[int] = []

        def is_parent(descriptor: int) -> bool:
            info = os.fstat(descriptor)
            return stat.S_ISDIR(info.st_mode) and (info.st_dev, info.st_ino) == parent_identity

        def fsync_parent_only(descriptor: int) -> None:
            if is_parent(descriptor):
                raise OSError("parent fsync failed")
            real_fsync(descriptor)

        def close_parent_then_fail(descriptor: int) -> None:
            parent = is_parent(descriptor)
            real_close(descriptor)
            if parent:
                failed_parent_closes.append(descriptor)
                raise OSError("close failed")

        with (
            mock.patch.object(envfiles_module, "_ensure_parent_directory"),
            mock.patch.object(envfiles_module, "verify_absolute_directory"),
        ):
            with mock.patch("hermes_bootstrap.envfiles.os.fsync", side_effect=fsync_parent_only):
                with mock.patch("hermes_bootstrap.envfiles.os.close", side_effect=close_parent_then_fail):
                    with self.assertRaises(ApplyError) as caught:
                        merge_env_file(
                            self.path,
                            {"GH_TOKEN": "parent-fsync-secret-marker"},
                            frozenset(),
                        )

        self.assertEqual(str(caught.exception), "could not synchronize environment file directory")
        self.assertGreaterEqual(len(failed_parent_closes), 1)
        self.assertIsNone(caught.exception.__cause__)
        self.assertIsNone(caught.exception.__context__)
        self.assert_exception_hides_markers(caught.exception, "parent-fsync-secret-marker")

    def test_parent_close_failure_is_sanitized_after_successful_fsync(self) -> None:
        self.path.parent.mkdir(parents=True)
        parent_info = self.path.parent.stat()
        parent_identity = (parent_info.st_dev, parent_info.st_ino)
        real_close = os.close
        failed_parent_closes: list[int] = []

        def close_parent_then_fail(descriptor: int) -> None:
            info = os.fstat(descriptor)
            parent = stat.S_ISDIR(info.st_mode) and (info.st_dev, info.st_ino) == parent_identity
            real_close(descriptor)
            if parent:
                failed_parent_closes.append(descriptor)
                raise OSError("close failed")

        with (
            mock.patch.object(envfiles_module, "_ensure_parent_directory"),
            mock.patch.object(envfiles_module, "verify_absolute_directory"),
        ):
            with mock.patch("hermes_bootstrap.envfiles.os.close", side_effect=close_parent_then_fail):
                with self.assertRaises(ApplyError) as caught:
                    merge_env_file(
                        self.path,
                        {"GH_TOKEN": "parent-close-secret-marker"},
                        frozenset(),
                    )

        self.assertEqual(str(caught.exception), "could not synchronize environment file directory")
        self.assertGreaterEqual(len(failed_parent_closes), 1)
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
                side_effect=("signing-secret", API_KEY_BODY),
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
                "API_SERVER_KEY": f"hermes-bootstrap-v1_{API_KEY_BODY}",
            },
        )
        for secret in (
            "dashboard-user",
            "dashboard-password",
            "hashed-password",
            "signing-secret",
            f"hermes-bootstrap-v1_{API_KEY_BODY}",
        ):
            self.assertNotIn(secret, repr(dashboard))

        root_environment = build_profile_environment("default", secrets, dashboard)
        rick_environment = build_profile_environment("rick", secrets, dashboard)
        self.assertIsInstance(root_environment, MappingProxyType)
        self.assertEqual(root_environment["SLACK_BOT_TOKEN"], "default-bot")
        self.assertEqual(rick_environment["SLACK_BOT_TOKEN"], "rick-bot")
        for key in GITHUB_KEYS | DASHBOARD_KEYS:
            self.assertEqual(root_environment[key], rick_environment[key])
        self.assertEqual(
            root_environment["API_SERVER_KEY"],
            f"hermes-bootstrap-v1_{API_KEY_BODY}",
        )
        self.assertNotIn("API_SERVER_KEY", rick_environment)
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
                "HERMES_DASHBOARD_BASIC_AUTH_SECRET": API_KEY_BODY[::-1],
                "API_SERVER_KEY": f"hermes-bootstrap-v1_{API_KEY_BODY}",
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
            API_KEY_BODY[::-1],
        )
        self.assertEqual(
            dashboard["API_SERVER_KEY"],
            f"hermes-bootstrap-v1_{API_KEY_BODY}",
        )

    def test_dashboard_rotates_an_unmanaged_or_weak_existing_api_key(self) -> None:
        existing = MappingProxyType(
            {
                "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH": "existing-hash",
                "HERMES_DASHBOARD_BASIC_AUTH_SECRET": API_KEY_BODY[::-1],
                "API_SERVER_KEY": f"hermes-bootstrap-v1_{'a' * 64}",
            }
        )

        with mock.patch("hermes_bootstrap.envfiles._verify_password", return_value=True):
            with mock.patch(
                "hermes_bootstrap.envfiles.secrets.token_urlsafe",
                return_value=API_KEY_BODY[::-1],
            ) as token_urlsafe:
                dashboard = build_dashboard_environment(secret_bundle(), existing)

        token_urlsafe.assert_called_once_with(48)
        self.assertEqual(
            dashboard["API_SERVER_KEY"],
            f"hermes-bootstrap-v1_{API_KEY_BODY[::-1]}",
        )

    def test_dashboard_rotates_a_weak_existing_signing_secret(self) -> None:
        existing = MappingProxyType(
            {
                "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH": "existing-hash",
                "HERMES_DASHBOARD_BASIC_AUTH_SECRET": "a" * 64,
                "API_SERVER_KEY": f"hermes-bootstrap-v1_{API_KEY_BODY}",
            }
        )

        with mock.patch("hermes_bootstrap.envfiles._verify_password", return_value=True):
            with mock.patch(
                "hermes_bootstrap.envfiles.secrets.token_urlsafe",
                return_value=API_KEY_BODY[::-1],
            ) as token_urlsafe:
                dashboard = build_dashboard_environment(secret_bundle(), existing)

        token_urlsafe.assert_called_once_with(48)
        self.assertEqual(
            dashboard["HERMES_DASHBOARD_BASIC_AUTH_SECRET"], API_KEY_BODY[::-1]
        )
        self.assertEqual(
            dashboard["API_SERVER_KEY"], f"hermes-bootstrap-v1_{API_KEY_BODY}"
        )

    def test_reads_only_unique_requested_values_from_a_regular_environment_file(self) -> None:
        self.path.parent.mkdir(parents=True)
        self.path.write_text(
            "KEEP=visible\n"
            "  export HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH = \"existing-hash\"\n"
            "HERMES_DASHBOARD_BASIC_AUTH_SECRET='existing-secret'\n",
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

    def test_read_environment_values_discards_duplicate_requested_assignments(self) -> None:
        self.path.parent.mkdir(parents=True)
        self.path.write_text(
            f"API_SERVER_KEY=hermes-bootstrap-v1_{API_KEY_BODY}\n"
            f"export API_SERVER_KEY='hermes-bootstrap-v1_{API_KEY_BODY}'\n",
            encoding="utf-8",
        )

        values = read_environment_values(self.path, API_SERVER_KEYS)

        self.assertNotIn("API_SERVER_KEY", values)

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
