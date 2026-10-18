"""Installation of shared Google Calendar MCP credentials."""

from __future__ import annotations

import stat
from collections.abc import Sequence
from pathlib import Path

import yaml

from .distributions import _atomic_write
from .errors import ApplyError, BootstrapError, ValidationError
from .mcp_config import install_mcp_configurations, load_managed_config
from .payload import GoogleCalendarSecret, validate_google_calendar_secret

_DIRECTORY = "google-calendar-mcp"
_OAUTH_FILE = "gcp-oauth.keys.json"
_TOKENS_FILE = "tokens.json"


def _mcp_configuration(data_root: Path) -> dict[str, object]:
    credentials = data_root / _DIRECTORY
    return {
        "command": "npx",
        "args": [
            "--yes",
            "--package",
            "@cocal/google-calendar-mcp@2.6.2",
            "google-calendar-mcp",
        ],
        "connect_timeout": 300,
        "env": {
            "GOOGLE_OAUTH_CREDENTIALS": str(credentials / _OAUTH_FILE),
            "GOOGLE_CALENDAR_MCP_TOKEN_PATH": str(credentials / _TOKENS_FILE),
        },
    }


def install_google_calendar_configurations(
    targets: Sequence[Path],
) -> None:
    """Install the same stdio MCP entry in root and every named profile."""

    try:
        if not targets:
            raise ValueError
        configuration = _mcp_configuration(targets[0])
        install_mcp_configurations(
            targets,
            "calendar",
            configuration,
            skip_invalid=True,
        )
    except (OSError, TypeError, UnicodeError, ValueError, yaml.YAMLError):
        raise ApplyError(
            "could not install Google Calendar MCP configuration"
        ) from None


def install_google_calendar_credentials(
    data_root: Path,
    secret: GoogleCalendarSecret,
) -> None:
    """Install one shared credential set without depending on a named profile."""

    target = data_root / _DIRECTORY
    try:
        if not stat.S_ISDIR(data_root.lstat().st_mode):
            raise OSError
        try:
            directory = target.lstat()
        except FileNotFoundError:
            target.mkdir(mode=0o700)
            directory = target.lstat()
        if not stat.S_ISDIR(directory.st_mode):
            raise OSError
        contents = {
            _OAUTH_FILE: secret.oauth_credentials_json.encode("utf-8"),
            _TOKENS_FILE: secret.tokens_json.encode("utf-8"),
        }
        for name in contents:
            path = target / name
            try:
                metadata = path.lstat()
            except FileNotFoundError:
                continue
            if not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1:
                raise OSError
        target.chmod(0o700)
        for name, content in contents.items():
            _atomic_write(target / name, content, 0o600)
    except (OSError, TypeError, UnicodeError, ValueError):
        raise ApplyError("could not install Google Calendar credentials") from None


def validate_google_calendar_installation(
    data_root: Path,
    targets: Sequence[Path],
) -> None:
    """Validate the shared credentials and every managed Calendar MCP entry."""

    try:
        if not targets:
            raise ValueError
        configuration = _mcp_configuration(targets[0])
        for target in targets:
            candidate = load_managed_config(target / "config.yaml")
            if candidate is None or candidate[2].get("calendar") != configuration:
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
        for name in (_OAUTH_FILE, _TOKENS_FILE):
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

        validate_google_calendar_secret(
            GoogleCalendarSecret(
                oauth_credentials_json=contents[_OAUTH_FILE],
                tokens_json=contents[_TOKENS_FILE],
            )
        )
    except (BootstrapError, OSError, TypeError, UnicodeError, ValueError):
        raise ValidationError(
            "installed Google Calendar configuration is invalid"
        ) from None
