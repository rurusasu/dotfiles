"""Install shared Google Gmail MCP credentials while preserving local tokens."""

from __future__ import annotations

import json
import os
import stat
from collections.abc import Sequence
from pathlib import Path

import yaml

from .errors import ApplyError, BootstrapError, ValidationError
from .mcp_config import install_mcp_configurations, load_managed_config
from .payload import GoogleCalendarSecret, validate_google_oauth_client

_DIRECTORY = "google-gmail-mcp"
_OAUTH_FILE = "gcp-oauth.keys.json"
_CREDENTIALS_FILE = "credentials.json"
_TOOLS = [
    "search_emails",
    "read_email",
    "get_thread",
    "list_inbox_threads",
    "get_inbox_with_threads",
    "list_email_labels",
    "draft_email",
]


def _mcp_configuration(data_root: Path) -> dict[str, object]:
    credentials = data_root / _DIRECTORY
    return {
        "command": "npx",
        "args": ["--yes", "--package", "@artymclabin/gmail-mcp@1.2.3", "gmail-mcp"],
        "connect_timeout": 300,
        "env": {
            "GMAIL_OAUTH_PATH": str(credentials / _OAUTH_FILE),
            "GMAIL_CREDENTIALS_PATH": str(credentials / _CREDENTIALS_FILE),
        },
        "tools": {"include": _TOOLS, "resources": False, "prompts": False},
    }


def install_google_gmail_configurations(targets: Sequence[Path]) -> None:
    """Install the same Gmail MCP entry in root and every named profile."""

    try:
        if not targets:
            raise ValueError
        configuration = _mcp_configuration(targets[0])
        install_mcp_configurations(
            targets,
            "gmail",
            configuration,
            skip_invalid=True,
        )
    except (OSError, TypeError, UnicodeError, ValueError, yaml.YAMLError):
        raise ApplyError("could not install Google Gmail MCP configuration") from None


def validate_google_gmail_installation(
    data_root: Path,
    targets: Sequence[Path],
) -> None:
    """Validate the shared credentials and every managed Gmail MCP entry."""

    try:
        if not targets:
            raise ValueError
        configuration = _mcp_configuration(targets[0])
        for target in targets:
            candidate = load_managed_config(target / "config.yaml")
            if candidate is None or candidate[2].get("gmail") != configuration:
                raise ValueError

        credentials = data_root / _DIRECTORY
        directory = credentials.lstat()
        if (
            stat.S_ISLNK(directory.st_mode)
            or not stat.S_ISDIR(directory.st_mode)
            or stat.S_IMODE(directory.st_mode) != 0o700
        ):
            raise ValueError

        oauth_path = credentials / _OAUTH_FILE
        metadata = oauth_path.lstat()
        if (
            not stat.S_ISREG(metadata.st_mode)
            or metadata.st_nlink != 1
            or stat.S_IMODE(metadata.st_mode) != 0o600
        ):
            raise ValueError
        validate_google_oauth_client(oauth_path.read_text(encoding="utf-8"))
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
            _validate_runtime_credentials(credentials_path.read_text(encoding="utf-8"))
    except (
        BootstrapError,
        OSError,
        TypeError,
        UnicodeError,
        ValueError,
        yaml.YAMLError,
    ):
        raise ValidationError(
            "installed Google Gmail configuration is invalid"
        ) from None


def install_google_gmail_credentials(
    data_root: Path,
    secret: GoogleCalendarSecret,
) -> None:
    """Reuse Calendar's OAuth client while preserving host-local Gmail tokens."""

    from .distributions import _atomic_write

    target = data_root / _DIRECTORY
    try:
        metadata = data_root.lstat()
        if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
            raise OSError
        try:
            directory = target.lstat()
        except FileNotFoundError:
            target.mkdir(mode=0o700)
            directory = target.lstat()
        if not stat.S_ISDIR(directory.st_mode):
            raise OSError
        content = secret.oauth_credentials_json.encode("utf-8")
        for name in (_OAUTH_FILE, _CREDENTIALS_FILE):
            path = target / name
            try:
                metadata = path.lstat()
            except FileNotFoundError:
                continue
            if not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1:
                raise OSError
        target.chmod(0o700)
        _atomic_write(target / _OAUTH_FILE, content, 0o600)
    except (OSError, TypeError, UnicodeError, ValueError):
        raise ApplyError("could not install Google Gmail credentials") from None


def _validate_runtime_credentials(raw: str) -> None:
    try:
        value = json.loads(raw)
        tokens = value["tokens"]
        scopes = value["scopes"]
    except (KeyError, TypeError, ValueError):
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

    return (
        isinstance(value, dict)
        and value.get("command") == "npx"
        and value.get("args")
        == ["--yes", "--package", "@artymclabin/gmail-mcp@1.2.3", "gmail-mcp"]
    )
