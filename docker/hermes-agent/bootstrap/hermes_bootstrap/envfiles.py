"""Atomic ownership of Hermes runtime environment files."""

from __future__ import annotations

import os
import re
import secrets
import stat
import tempfile
from collections.abc import Mapping
from dataclasses import dataclass
from io import StringIO
from pathlib import Path
from types import MappingProxyType
from typing import AbstractSet

from dotenv.parser import parse_stream
from plugins.dashboard_auth.basic import _verify_password, hash_password

from .errors import ApplyError, BootstrapError, InputError
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
    original = _read_regular_file(path)
    canonical = _canonical_environment_bytes(original, managed, remove)

    if original is not None and original == canonical:
        _chmod_private(path)
        return False

    _atomic_write(path, canonical)
    return True


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

    missing: list[Path] = []
    current = parent
    while True:
        try:
            metadata = current.lstat()
        except FileNotFoundError:
            missing.append(current)
            if current.parent == current:
                raise ApplyError("environment file parent is invalid") from None
            current = current.parent
            continue
        if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
            raise ApplyError("environment file parent is not a regular directory")
        break

    for directory in reversed(missing):
        try:
            directory.mkdir()
            metadata = directory.lstat()
        except OSError:
            raise ApplyError("could not create environment file parent") from None
        if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
            raise ApplyError("environment file parent is not a regular directory")


def _read_regular_file(path: Path) -> bytes | None:
    try:
        metadata = path.lstat()
    except FileNotFoundError:
        return None
    except OSError:
        raise ApplyError("could not inspect environment file") from None
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
        raise ApplyError("environment file is not a regular file")
    try:
        return path.read_bytes()
    except OSError:
        raise ApplyError("could not read environment file") from None


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


def _chmod_private(path: Path) -> None:
    try:
        os.chmod(path, 0o600, follow_symlinks=False)
    except (NotImplementedError, OSError):
        raise ApplyError("could not set environment file permissions") from None


def _atomic_write(path: Path, content: bytes) -> None:
    descriptor: int | None = None
    temporary: str | None = None
    failure: ApplyError | None = None
    try:
        descriptor, temporary = tempfile.mkstemp(
            prefix=f"{path.name}.", suffix=".tmp", dir=path.parent
        )
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "wb") as stream:
            descriptor = None
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        temporary = None
    except OSError:
        failure = ApplyError("could not atomically update environment file")

    cleanup_failed = False
    if descriptor is not None:
        try:
            os.close(descriptor)
        except OSError:
            cleanup_failed = True
    if temporary is not None:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        except OSError:
            cleanup_failed = True

    if failure is not None:
        raise failure
    if cleanup_failed:
        raise ApplyError("could not atomically update environment file")

    _fsync_parent(path.parent)


def _fsync_parent(parent: Path) -> None:
    descriptor: int | None = None
    failure: ApplyError | None = None
    try:
        flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0)
        descriptor = os.open(parent, flags)
        os.fsync(descriptor)
    except OSError:
        failure = ApplyError("could not synchronize environment file directory")

    cleanup_failed = False
    if descriptor is not None:
        try:
            os.close(descriptor)
        except OSError:
            cleanup_failed = True

    if failure is not None:
        raise failure
    if cleanup_failed:
        raise ApplyError("could not synchronize environment file directory")
