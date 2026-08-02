"""Transactional installation of Google Gmail MCP configurations."""

from __future__ import annotations

import os
import stat
from collections.abc import Sequence
from pathlib import Path

import yaml

from .errors import ApplyError, BootstrapError, ValidationError
from .transaction import Transaction


_MCP_CONFIGURATION = {
    "url": "https://gmailmcp.googleapis.com/mcp/v1",
    "auth": "oauth",
    "connect_timeout": 315,
    "oauth": {
        "client_id": "${GMAIL_MCP_CLIENT_ID}",
        "client_secret": "${GMAIL_MCP_CLIENT_SECRET}",
        "scope": (
            "https://www.googleapis.com/auth/gmail.readonly "
            "https://www.googleapis.com/auth/gmail.compose"
        ),
    },
    "tools": {
        "include": [
            "search_threads",
            "get_thread",
            "get_message",
            "list_labels",
            "list_drafts",
            "create_draft",
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
    """Validate every managed Gmail MCP configuration."""

    del data_root
    try:
        for target in targets:
            candidate = _load_managed_config(target / "config.yaml")
            if candidate is None or candidate[2].get("gmail") != _MCP_CONFIGURATION:
                raise ValueError
    except (BootstrapError, OSError, TypeError, UnicodeError, ValueError, yaml.YAMLError):
        raise ValidationError("installed Google Gmail configuration is invalid") from None


def _gmail_configuration() -> dict[str, object]:
    return {
        "url": _MCP_CONFIGURATION["url"],
        "auth": _MCP_CONFIGURATION["auth"],
        "connect_timeout": _MCP_CONFIGURATION["connect_timeout"],
        "oauth": dict(_MCP_CONFIGURATION["oauth"]),
        "tools": {
            "include": list(_MCP_CONFIGURATION["tools"]["include"]),
            "resources": _MCP_CONFIGURATION["tools"]["resources"],
            "prompts": _MCP_CONFIGURATION["tools"]["prompts"],
        },
    }


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
