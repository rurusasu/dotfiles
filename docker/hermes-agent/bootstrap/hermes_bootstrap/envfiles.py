"""Atomic ownership of Hermes runtime environment files."""

from __future__ import annotations

import os
import re
import secrets
import stat
from collections.abc import Mapping
from dataclasses import dataclass
from io import StringIO
from pathlib import Path
from types import MappingProxyType
from typing import AbstractSet

from dotenv.parser import parse_stream
from plugins.dashboard_auth.basic import _verify_password, hash_password

from .errors import ApplyError, BootstrapError, InputError
from .filesystem import open_absolute_directory, verify_absolute_directory
from .payload import SecretBundle


GITHUB_KEYS = frozenset(
    {
        "GITHUB_PERSONAL_ACCESS_TOKEN",
        "GH_TOKEN",
        "GITHUB_TOKEN",
    }
)
DASHBOARD_KEYS = frozenset(
    {
        "HERMES_DASHBOARD_BASIC_AUTH_USERNAME",
        "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH",
        "HERMES_DASHBOARD_BASIC_AUTH_SECRET",
    }
)
API_SERVER_KEYS = frozenset({"API_SERVER_KEY"})
SLACK_KEYS = frozenset(
    {
        "SLACK_BOT_TOKEN",
        "SLACK_APP_TOKEN",
        "SLACK_ALLOWED_USERS",
    }
)
_PLAINTEXT_DASHBOARD_PASSWORD = "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD"
_ENV_KEY = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
_ENVIRONMENT_LINE_KEY = re.compile(
    r"^[ \t]*(?:export[ \t]+)?([A-Za-z_][A-Za-z0-9_]*)(?=[ \t=]|$)"
)
_API_SERVER_KEY_PREFIX = "hermes-bootstrap-v1_"
_RANDOM_SECRET_BODY = re.compile(r"[A-Za-z0-9_-]{64}\Z")


class _SecretEnvironmentValue(str):
    """A normal environment value whose diagnostic representation is safe."""

    def __repr__(self) -> str:
        return "'[REDACTED]'"


@dataclass(frozen=True)
class _EnvironmentFailure:
    """A non-sensitive failure passed out of a secret-bearing boundary."""

    error_type: type[BootstrapError]
    message: str


def merge_env_file(
    path: Path, managed: Mapping[str, str], remove: AbstractSet[str]
) -> bool:
    """Atomically replace only the bootstrap-owned assignments in ``path``.

    A canonical second apply never replaces the destination inode.  It does,
    however, correct the file mode because environment files always contain
    credentials after bootstrap has run.
    """

    outcome = _merge_env_file_boundary(path, managed, remove)
    del managed, remove
    if isinstance(outcome, _EnvironmentFailure):
        error_type = outcome.error_type
        message = outcome.message
        del outcome
        raise error_type(message)
    return outcome


def _merge_env_file_boundary(
    path: Path, managed: Mapping[str, str], remove: AbstractSet[str]
) -> bool | _EnvironmentFailure:
    try:
        return _merge_env_file(path, managed, remove)
    except BootstrapError as error:
        return _EnvironmentFailure(type(error), str(error))


def _merge_env_file(path: Path, managed: Mapping[str, str], remove: AbstractSet[str]) -> bool:
    _validate_environment_mapping(managed, remove)
    _ensure_parent_directory(path.parent)
    parent_descriptor = _open_environment_parent(path.parent)
    original_descriptor: int | None = None
    try:
        original_descriptor = _open_regular_file_at(parent_descriptor, path.name)
        original = (
            None
            if original_descriptor is None
            else _read_open_regular_file(original_descriptor)
        )
        canonical = _canonical_environment_bytes(original, managed, remove)
        try:
            verify_absolute_directory(path.parent, parent_descriptor)
        except (OSError, ValueError):
            raise ApplyError("environment file parent is not a regular directory") from None
        if original is not None and original == canonical:
            if original_descriptor is None:
                raise ApplyError("environment file changed unexpectedly")
            _chmod_private_at(parent_descriptor, path.name, original_descriptor)
            result = False
        else:
            _atomic_write_at(parent_descriptor, path.name, canonical)
            result = True
    except Exception:
        _close_environment_descriptors(original_descriptor, parent_descriptor)
        raise
    if _close_environment_descriptors(original_descriptor, parent_descriptor):
        raise ApplyError("could not synchronize environment file directory") from None
    return result


def read_environment_values(path: Path, keys: AbstractSet[str]) -> Mapping[str, str]:
    """Read unique requested assignments without exposing values in diagnostics."""

    for key in keys:
        _validate_environment_key(key)
    original = _read_regular_file(path)
    if original is None:
        return _private_mapping({})
    try:
        text = original.decode("utf-8").replace("\r\n", "\n").replace("\r", "\n")
    except UnicodeDecodeError:
        raise ApplyError("environment file is not valid UTF-8") from None

    values: dict[str, str] = {}
    duplicates: set[str] = set()
    for binding in parse_stream(StringIO(text)):
        key = binding.key
        if binding.error or key is None or key not in keys or key in duplicates:
            continue
        value = binding.value
        if not isinstance(value, str):
            continue
        if key in values:
            values.pop(key)
            duplicates.add(key)
            continue
        values[key] = value
    return _private_mapping(values)


def build_dashboard_environment(
    bundle: SecretBundle, existing: Mapping[str, str] | None = None
) -> Mapping[str, str]:
    """Derive the one shared, plaintext-free dashboard environment mapping."""

    outcome = _build_dashboard_environment_boundary(bundle, existing or {})
    del bundle, existing
    if isinstance(outcome, _EnvironmentFailure):
        error_type = outcome.error_type
        message = outcome.message
        del outcome
        raise error_type(message)
    return outcome


def _build_dashboard_environment_boundary(
    bundle: SecretBundle, existing: Mapping[str, str]
) -> Mapping[str, str] | _EnvironmentFailure:
    try:
        return _build_dashboard_environment(bundle, existing)
    except BootstrapError as error:
        return _EnvironmentFailure(type(error), str(error))


def _build_dashboard_environment(
    bundle: SecretBundle, existing: Mapping[str, str]
) -> Mapping[str, str]:
    try:
        username = bundle.dashboard.username
        password = bundle.dashboard.password
        existing_hash = existing.get("HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH", "")
        password_hash = (
            existing_hash
            if isinstance(existing_hash, str)
            and _verify_password(password, existing_hash)
            else hash_password(password)
        )
        existing_secret = existing.get("HERMES_DASHBOARD_BASIC_AUTH_SECRET", "")
        signing_secret = (
            existing_secret
            if _is_reusable_signing_secret(existing_secret)
            else secrets.token_urlsafe(48)
        )
        existing_api_key = existing.get("API_SERVER_KEY", "")
        api_key = (
            existing_api_key
            if _is_reusable_api_server_key(existing_api_key)
            else _API_SERVER_KEY_PREFIX + secrets.token_urlsafe(48)
        )
        result = {
            "HERMES_DASHBOARD_BASIC_AUTH_USERNAME": username,
            "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH": password_hash,
            "HERMES_DASHBOARD_BASIC_AUTH_SECRET": signing_secret,
            "API_SERVER_KEY": api_key,
        }
        _validate_environment_mapping(result, frozenset())
    except (AttributeError, TypeError, ValueError):
        raise InputError("dashboard credentials are invalid") from None
    except Exception:
        raise ApplyError("dashboard credential derivation failed") from None
    return _private_mapping(result)


def build_profile_environment(
    profile: str, secrets: SecretBundle, dashboard: Mapping[str, str]
) -> Mapping[str, str]:
    """Build the complete immutable environment for root/default or one profile."""

    outcome = _build_profile_environment_boundary(profile, secrets, dashboard)
    del secrets, dashboard
    if isinstance(outcome, _EnvironmentFailure):
        error_type = outcome.error_type
        message = outcome.message
        del outcome
        raise error_type(message)
    return outcome


def _build_profile_environment_boundary(
    profile: str, secrets: SecretBundle, dashboard: Mapping[str, str]
) -> Mapping[str, str] | _EnvironmentFailure:
    try:
        return _build_profile_environment(profile, secrets, dashboard)
    except BootstrapError as error:
        return _EnvironmentFailure(type(error), str(error))


def _build_profile_environment(
    profile: str, secrets: SecretBundle, dashboard: Mapping[str, str]
) -> Mapping[str, str]:
    try:
        slack = secrets.slack_by_profile[profile]
    except (AttributeError, KeyError, TypeError):
        raise InputError("profile has no declared Slack credentials") from None

    environment = {
        "GITHUB_PERSONAL_ACCESS_TOKEN": secrets.github_token,
        "GH_TOKEN": secrets.github_token,
        "GITHUB_TOKEN": secrets.github_token,
    }
    _validate_dashboard_mapping(dashboard)
    environment.update({key: dashboard[key] for key in DASHBOARD_KEYS})
    if profile == "default":
        environment.update({key: dashboard[key] for key in API_SERVER_KEYS})
    environment.update(
        {
            "SLACK_BOT_TOKEN": slack.bot_token,
            "SLACK_APP_TOKEN": slack.app_token,
            "SLACK_ALLOWED_USERS": slack.allowed_users,
        }
    )
    _validate_environment_mapping(environment, frozenset())
    return _private_mapping(environment)


def _validate_dashboard_mapping(dashboard: Mapping[str, str]) -> None:
    if set(dashboard) != DASHBOARD_KEYS | API_SERVER_KEYS:
        raise InputError("dashboard environment mapping is invalid")
    _validate_environment_mapping(dashboard, frozenset())


def _is_reusable_api_server_key(value: object) -> bool:
    if not isinstance(value, str) or not value.startswith(_API_SERVER_KEY_PREFIX):
        return False
    body = value.removeprefix(_API_SERVER_KEY_PREFIX)
    return _is_reusable_random_secret(body)


def _is_reusable_signing_secret(value: object) -> bool:
    return isinstance(value, str) and _is_reusable_random_secret(value)


def _is_reusable_random_secret(value: str) -> bool:
    return _RANDOM_SECRET_BODY.fullmatch(value) is not None and len(set(value)) >= 16


def _private_mapping(values: Mapping[str, str]) -> Mapping[str, str]:
    return MappingProxyType(
        {key: _SecretEnvironmentValue(value) for key, value in values.items()}
    )


def _validate_environment_mapping(managed: Mapping[str, str], remove: AbstractSet[str]) -> None:
    try:
        items = tuple(managed.items())
        removed = tuple(remove)
    except (AttributeError, TypeError):
        raise InputError("environment mapping is invalid") from None
    for key, value in items:
        _validate_environment_key(key)
        # python-dotenv expands ${NAME} even in single-quoted values.
        if (
            not isinstance(value, str)
            or any(character in value for character in "\x00\r\n")
            or "${" in value
        ):
            raise InputError("environment value is invalid")
    for key in removed:
        _validate_environment_key(key)


def _validate_environment_key(key: object) -> None:
    if not isinstance(key, str) or not _ENV_KEY.fullmatch(key):
        raise InputError("environment key is invalid")


def _ensure_parent_directory(parent: Path) -> None:
    """Create missing parents while rejecting symlinked or non-directory nodes."""

    descriptor: int | None = None
    try:
        descriptor = open_absolute_directory(parent, create=True)
    except (OSError, ValueError):
        raise ApplyError("environment file parent is not a regular directory") from None
    finally:
        if descriptor is not None:
            os.close(descriptor)


def _open_environment_parent(parent: Path) -> int:
    try:
        return open_absolute_directory(parent)
    except (OSError, ValueError):
        raise ApplyError("environment file parent is not a regular directory") from None


def _read_regular_file(path: Path) -> bytes | None:
    try:
        parent_descriptor = open_absolute_directory(path.parent)
    except FileNotFoundError:
        return None
    except (OSError, ValueError):
        raise ApplyError("could not inspect environment file") from None
    try:
        return _read_regular_file_at(parent_descriptor, path.name)
    finally:
        os.close(parent_descriptor)


def _read_regular_file_at(parent_descriptor: int, name: str) -> bytes | None:
    descriptor = _open_regular_file_at(parent_descriptor, name)
    if descriptor is None:
        return None
    try:
        return _read_open_regular_file(descriptor)
    finally:
        os.close(descriptor)


def _open_regular_file_at(parent_descriptor: int, name: str) -> int | None:
    descriptor: int | None = None
    try:
        flags = os.O_RDONLY | os.O_CLOEXEC | os.O_NONBLOCK
        if hasattr(os, "O_NOFOLLOW"):
            flags |= os.O_NOFOLLOW
        descriptor = os.open(name, flags, dir_fd=parent_descriptor)
    except FileNotFoundError:
        return None
    except OSError:
        raise ApplyError("could not inspect environment file") from None
    try:
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1:
            raise ApplyError("environment file is not a private regular file")
        result = descriptor
        descriptor = None
        return result
    except OSError:
        raise ApplyError("could not inspect environment file") from None
    finally:
        if descriptor is not None:
            os.close(descriptor)


def _read_open_regular_file(descriptor: int) -> bytes:
    duplicate: int | None = None
    try:
        duplicate = os.dup(descriptor)
        with os.fdopen(duplicate, "rb") as stream:
            duplicate = None
            return stream.read()
    except OSError:
        raise ApplyError("could not read environment file") from None
    finally:
        if duplicate is not None:
            os.close(duplicate)


def _canonical_environment_bytes(
    original: bytes | None, managed: Mapping[str, str], remove: AbstractSet[str]
) -> bytes:
    owned = set(managed) | set(remove) | {_PLAINTEXT_DASHBOARD_PASSWORD}
    if original is None:
        lines: list[str] = []
    else:
        try:
            source = original.decode("utf-8")
        except UnicodeDecodeError:
            raise ApplyError("environment file is not valid UTF-8") from None
        source = source.replace("\r\n", "\n").replace("\r", "\n")
        preserved: list[str] = []
        discard_continuation = False
        for binding in parse_stream(StringIO(source)):
            original_binding = binding.original.string
            discard = discard_continuation or _binding_environment_key(binding.key, original_binding) in owned
            if not discard:
                preserved.append(original_binding)
            discard_continuation = discard and _has_trailing_line_continuation(original_binding)
        preserved_source = "".join(preserved)
        lines = preserved_source.split("\n")
        if lines and lines[-1] == "":
            lines.pop()

    managed_lines = [f"{key}={_quote_environment_value(managed[key])}" for key in managed]
    if lines and managed_lines and lines[-1] != "":
        lines.append("")
    return ("\n".join([*lines, *managed_lines]) + "\n").encode("utf-8")


def _quote_environment_value(value: str) -> str:
    return "'" + value.replace("\\", "\\\\").replace("'", "\\'") + "'"


def _binding_environment_key(key: str | None, original: str) -> str | None:
    if key is not None:
        return key
    first_line = original.split("\n", 1)[0]
    return _environment_line_key(first_line)


def _has_trailing_line_continuation(original: str) -> bool:
    if not original.endswith("\n"):
        return False
    final_line = original[:-1].rsplit("\n", 1)[-1]
    trailing_backslashes = len(final_line) - len(final_line.rstrip("\\"))
    return trailing_backslashes % 2 == 1


def _environment_line_key(line: str) -> str | None:
    match = _ENVIRONMENT_LINE_KEY.match(line)
    return match.group(1) if match else None


def _chmod_private_at(parent_descriptor: int, name: str, descriptor: int) -> None:
    try:
        _verify_open_regular_file_at(parent_descriptor, name, descriptor)
        os.fchmod(descriptor, 0o600)
        _verify_open_regular_file_at(parent_descriptor, name, descriptor)
    except (NotImplementedError, OSError):
        raise ApplyError("could not set environment file permissions") from None


def _verify_open_regular_file_at(parent_descriptor: int, name: str, descriptor: int) -> None:
    try:
        opened = os.fstat(descriptor)
        current = os.stat(name, dir_fd=parent_descriptor, follow_symlinks=False)
    except OSError:
        raise ApplyError("environment file changed unexpectedly") from None
    if (
        not stat.S_ISREG(opened.st_mode)
        or not stat.S_ISREG(current.st_mode)
        or opened.st_nlink != 1
        or current.st_nlink != 1
        or (opened.st_dev, opened.st_ino) != (current.st_dev, current.st_ino)
    ):
        raise ApplyError("environment file changed unexpectedly")


def _close_environment_descriptors(*descriptors: int | None) -> bool:
    failed = False
    for descriptor in descriptors:
        if descriptor is None:
            continue
        try:
            os.close(descriptor)
        except OSError:
            failed = True
    return failed


def _atomic_write_at(parent_descriptor: int, name: str, content: bytes) -> None:
    descriptor: int | None = None
    temporary: str | None = None
    failure: ApplyError | None = None
    try:
        for _attempt in range(128):
            temporary = f"{name}.{secrets.token_hex(8)}.tmp"
            try:
                descriptor = os.open(
                    temporary,
                    os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC,
                    0o600,
                    dir_fd=parent_descriptor,
                )
                break
            except FileExistsError:
                continue
        else:
            raise OSError("could not allocate temporary environment file")
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "wb") as stream:
            descriptor = None
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(
            temporary,
            name,
            src_dir_fd=parent_descriptor,
            dst_dir_fd=parent_descriptor,
        )
        temporary = None
    except OSError:
        failure = ApplyError("could not atomically update environment file")

    if failure is None:
        try:
            os.fsync(parent_descriptor)
        except OSError:
            failure = ApplyError("could not synchronize environment file directory")

    cleanup_failed = False
    if descriptor is not None:
        try:
            os.close(descriptor)
        except OSError:
            cleanup_failed = True
    if temporary is not None:
        try:
            os.unlink(temporary, dir_fd=parent_descriptor)
        except FileNotFoundError:
            pass
        except OSError:
            cleanup_failed = True

    if failure is not None:
        raise failure
    if cleanup_failed:
        raise ApplyError("could not atomically update environment file")
