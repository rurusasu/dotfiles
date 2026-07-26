"""Transactional installation of shared Google Calendar MCP credentials."""

from __future__ import annotations

import os
import stat
from collections.abc import Sequence
from pathlib import Path

import yaml

from .distributions import _atomic_write
from .errors import ApplyError
from .payload import GoogleCalendarSecret
from .transaction import Transaction


_DIRECTORY = "google-calendar-mcp"
_OAUTH_FILE = "gcp-oauth.keys.json"
_TOKENS_FILE = "tokens.json"
_MCP_CONFIGURATION = {
    "command": "google-calendar-mcp",
    "connect_timeout": 300,
    "env": {
        "GOOGLE_OAUTH_CREDENTIALS": (
            "/opt/data/google-calendar-mcp/gcp-oauth.keys.json"
        ),
        "GOOGLE_CALENDAR_MCP_TOKEN_PATH": (
            "/opt/data/google-calendar-mcp/tokens.json"
        ),
    },
}


def install_google_calendar_configurations(
    targets: Sequence[Path],
    transaction: Transaction,
) -> None:
    """Install the same stdio MCP entry in root and every named profile."""

    try:
        for target in targets:
            path = target / "config.yaml"
            candidate = _load_managed_config(path)
            if candidate is None:
                # Final installed-layout validation owns replacement-race errors.
                continue
            metadata, config, mcp_servers = candidate
            if mcp_servers.get("calendar") == _MCP_CONFIGURATION:
                continue
            mcp_servers["calendar"] = {
                "command": _MCP_CONFIGURATION["command"],
                "connect_timeout": _MCP_CONFIGURATION["connect_timeout"],
                "env": dict(_MCP_CONFIGURATION["env"]),
            }
            transaction.snapshot(path)
            _atomic_write(
                path,
                yaml.safe_dump(config, sort_keys=False).encode("utf-8"),
                stat.S_IMODE(metadata.st_mode),
            )
    except (OSError, TypeError, UnicodeError, ValueError, yaml.YAMLError):
        raise ApplyError(
            "could not install Google Calendar MCP configuration"
        ) from None


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


def install_google_calendar_credentials(
    data_root: Path,
    secret: GoogleCalendarSecret,
    transaction: Transaction,
) -> None:
    """Install one shared credential set without depending on a named profile."""

    target = data_root / _DIRECTORY
    try:
        if _credentials_are_current(target, secret):
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
        _atomic_write(
            target / _TOKENS_FILE,
            secret.tokens_json.encode("utf-8"),
            0o600,
        )
    except (OSError, TypeError, UnicodeError, ValueError):
        raise ApplyError("could not install Google Calendar credentials") from None


def _credentials_are_current(
    target: Path,
    secret: GoogleCalendarSecret,
) -> bool:
    try:
        directory = target.lstat()
        if (
            stat.S_ISLNK(directory.st_mode)
            or not stat.S_ISDIR(directory.st_mode)
            or stat.S_IMODE(directory.st_mode) != 0o700
        ):
            return False
        expected = {
            _OAUTH_FILE: secret.oauth_credentials_json.encode("utf-8"),
            _TOKENS_FILE: secret.tokens_json.encode("utf-8"),
        }
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
