"""Transactional installation of shared Google Gmail MCP credentials."""

from __future__ import annotations

import os
import stat
from collections.abc import Sequence
from pathlib import Path

import yaml

from .errors import ApplyError, BootstrapError, ValidationError
from .payload import GoogleCalendarSecret, _google_calendar_oauth_client_values
from .transaction import Transaction


_DIRECTORY = "google-gmail-mcp"
_OAUTH_FILE = "gcp-oauth.keys.json"
_CREDENTIALS_FILE = "credentials.json"
_MCP_CONFIGURATION = {
    "command": "gmail-mcp",
    "connect_timeout": 300,
    "env": {
        "GMAIL_OAUTH_PATH": "/opt/data/google-gmail-mcp/gcp-oauth.keys.json",
        "GMAIL_CREDENTIALS_PATH": "/opt/data/google-gmail-mcp/credentials.json",
    },
    "tools": {
        "include": [
            "search_emails",
            "read_email",
            "get_thread",
            "list_inbox_threads",
            "get_inbox_with_threads",
            "list_email_labels",
            "draft_email",
        ],
        "resources": False,
        "prompts": False,
    },
}


def install_google_gmail_configurations(
    targets: Sequence[Path],
    transaction: Transaction,
) -> None:
    """Install the same Gmail MCP entry in root and every named profile."""

    from .distributions import _atomic_write

    try:
        for target in targets:
            path = target / "config.yaml"
            candidate = _load_managed_config(path)
            if candidate is None:
                # Final installed-layout validation owns replacement-race errors.
                continue
            metadata, config, mcp_servers = candidate
            if mcp_servers.get("gmail") == _MCP_CONFIGURATION:
                continue
            mcp_servers["gmail"] = _gmail_configuration()
            transaction.snapshot(path)
            _atomic_write(
                path,
                yaml.safe_dump(config, sort_keys=False).encode("utf-8"),
                stat.S_IMODE(metadata.st_mode),
            )
    except (OSError, TypeError, UnicodeError, ValueError, yaml.YAMLError):
        raise ApplyError("could not install Google Gmail MCP configuration") from None


def validate_google_gmail_installation(
    data_root: Path,
    targets: Sequence[Path],
) -> None:
    """Validate the shared credentials and every managed Gmail MCP entry."""

    try:
        for target in targets:
            candidate = _load_managed_config(target / "config.yaml")
            if candidate is None or candidate[2].get("gmail") != _MCP_CONFIGURATION:
                raise ValueError

        credentials = data_root / _DIRECTORY
        directory = credentials.lstat()
        if (
            stat.S_ISLNK(directory.st_mode)
            or not stat.S_ISDIR(directory.st_mode)
            or stat.S_IMODE(directory.st_mode) != 0o700
        ):
            raise ValueError

        contents: dict[str, str] = {}
        for name in (_OAUTH_FILE,):
            path = credentials / name
            metadata = path.lstat()
            if (
                stat.S_ISLNK(metadata.st_mode)
                or not stat.S_ISREG(metadata.st_mode)
                or metadata.st_nlink != 1
                or stat.S_IMODE(metadata.st_mode) != 0o600
            ):
                raise ValueError
            contents[name] = path.read_text(encoding="utf-8")

        _google_calendar_oauth_client_values(
            GoogleCalendarSecret(
                oauth_credentials_json=contents[_OAUTH_FILE],
                tokens_json='{"refresh_token":"unused"}',
            )
        )
        credentials_path = credentials / _CREDENTIALS_FILE
        if os.path.lexists(credentials_path):
            metadata = credentials_path.lstat()
            if (
                stat.S_ISLNK(metadata.st_mode)
                or not stat.S_ISREG(metadata.st_mode)
                or metadata.st_nlink != 1
                or stat.S_IMODE(metadata.st_mode) != 0o600
            ):
                raise ValueError
            _validate_runtime_credentials(
                credentials_path.read_text(encoding="utf-8")
            )
    except ValidationError:
        raise
    except (BootstrapError, OSError, TypeError, UnicodeError, ValueError, yaml.YAMLError):
        raise ValidationError("installed Google Gmail configuration is invalid") from None


def _gmail_configuration() -> dict[str, object]:
    return {
        "command": _MCP_CONFIGURATION["command"],
        "connect_timeout": _MCP_CONFIGURATION["connect_timeout"],
        "env": dict(_MCP_CONFIGURATION["env"]),
        "tools": {
            "include": list(_MCP_CONFIGURATION["tools"]["include"]),
            "resources": _MCP_CONFIGURATION["tools"]["resources"],
            "prompts": _MCP_CONFIGURATION["tools"]["prompts"],
        },
    }


def install_google_gmail_credentials(
    data_root: Path,
    secret: GoogleCalendarSecret,
    transaction: Transaction,
) -> None:
    """Reuse Calendar's OAuth client while preserving host-local Gmail tokens."""

    from .distributions import _atomic_write

    target = data_root / _DIRECTORY
    try:
        if _oauth_is_current(target, secret):
            return
        transaction.snapshot(target)
        if os.path.lexists(target):
            metadata = target.lstat()
            if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
                raise OSError
        else:
            target.mkdir(mode=0o700)
        target.chmod(0o700)
        _atomic_write(
            target / _OAUTH_FILE,
            secret.oauth_credentials_json.encode("utf-8"),
            0o600,
        )
    except (OSError, TypeError, UnicodeError, ValueError):
        raise ApplyError("could not install Google Gmail credentials") from None


def _oauth_is_current(target: Path, secret: GoogleCalendarSecret) -> bool:
    try:
        directory = target.lstat()
        if (
            stat.S_ISLNK(directory.st_mode)
            or not stat.S_ISDIR(directory.st_mode)
            or stat.S_IMODE(directory.st_mode) != 0o700
        ):
            return False
        expected = {_OAUTH_FILE: secret.oauth_credentials_json.encode("utf-8")}
        for name, content in expected.items():
            path = target / name
            metadata = path.lstat()
            if (
                stat.S_ISLNK(metadata.st_mode)
                or not stat.S_ISREG(metadata.st_mode)
                or metadata.st_nlink != 1
                or stat.S_IMODE(metadata.st_mode) != 0o600
                or path.read_bytes() != content
            ):
                return False
        return True
    except (OSError, TypeError, UnicodeError):
        return False


def _validate_runtime_credentials(raw: str) -> None:
    import json

    try:
        value = json.loads(raw)
        tokens = value["tokens"]
        scopes = value["scopes"]
    except (KeyError, TypeError, ValueError, json.JSONDecodeError):
        raise ValueError from None
    normalized = (
        {
            scope.removeprefix("https://www.googleapis.com/auth/")
            for scope in scopes
            if isinstance(scope, str)
        }
        if isinstance(scopes, list)
        else set()
    )
    if (
        not isinstance(tokens, dict)
        or not isinstance(tokens.get("refresh_token"), str)
        or not tokens["refresh_token"]
        or not {"gmail.readonly", "gmail.compose"} <= normalized
    ):
        raise ValueError


def is_google_gmail_configuration(value: object) -> bool:
    """Return whether a config entry is the bootstrap-owned Gmail declaration."""

    return value == _MCP_CONFIGURATION


def _load_managed_config(
    path: Path,
) -> tuple[os.stat_result, dict[object, object], dict[object, object]] | None:
    try:
        metadata = path.lstat()
        if (
            stat.S_ISLNK(metadata.st_mode)
            or not stat.S_ISREG(metadata.st_mode)
            or metadata.st_nlink != 1
        ):
            return None
        config = yaml.safe_load(path.read_text(encoding="utf-8"))
        if not isinstance(config, dict):
            return None
        mcp_servers = config.get("mcp_servers")
        if not isinstance(mcp_servers, dict):
            return None
        return metadata, config, mcp_servers
    except (OSError, UnicodeError, yaml.YAMLError):
        return None
