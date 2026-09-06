"""Transactional reconciliation of managed Hermes configuration sections."""

from __future__ import annotations

import os
import stat
from collections.abc import Sequence
from pathlib import Path

import yaml

from .distributions import _atomic_write
from .envfiles import LEGACY_SLACK_KEYS
from .errors import ApplyError
from .models import BootstrapManifest
from .onepassword import build_onepassword_config
from .transaction import Transaction


_XAPI_MCP = {
    "url": "http://xapi-mcp:8080/mcp",
    "connect_timeout": 300,
}


def reconcile_xapi_configurations(
    targets: Sequence[Path],
    transaction: Transaction,
) -> None:
    """Install the canonical internal X API MCP in every runtime profile."""

    try:
        for target in targets:
            path = target / "config.yaml"
            metadata = path.lstat()
            if (
                stat.S_ISLNK(metadata.st_mode)
                or not stat.S_ISREG(metadata.st_mode)
                or metadata.st_nlink != 1
            ):
                raise ApplyError("invalid Hermes X API configuration file")
            config = yaml.safe_load(path.read_text(encoding="utf-8"))
            if not isinstance(config, dict):
                raise ApplyError("invalid Hermes X API configuration")
            mcp_servers = config.get("mcp_servers")
            if mcp_servers is None:
                mcp_servers = {}
            if not isinstance(mcp_servers, dict):
                raise ApplyError("invalid Hermes X API configuration")
            if mcp_servers.get("xapi") == _XAPI_MCP:
                continue

            candidate = dict(config)
            candidate_servers = dict(mcp_servers)
            candidate_servers["xapi"] = dict(_XAPI_MCP)
            candidate["mcp_servers"] = candidate_servers
            content = yaml.safe_dump(candidate, sort_keys=False).encode("utf-8")
            transaction.snapshot(path)
            _atomic_write(path, content, stat.S_IMODE(metadata.st_mode))
    except ApplyError:
        raise
    except (OSError, TypeError, UnicodeError, ValueError, yaml.YAMLError):
        raise ApplyError("could not reconcile Hermes X API configuration") from None


def validate_xapi_configurations(targets: Sequence[Path]) -> None:
    """Require the canonical internal X API MCP in every runtime profile."""

    try:
        for target in targets:
            path = target / "config.yaml"
            metadata = path.lstat()
            if (
                stat.S_ISLNK(metadata.st_mode)
                or not stat.S_ISREG(metadata.st_mode)
                or metadata.st_nlink != 1
            ):
                raise ApplyError("installed Hermes X API configuration is invalid")
            config = yaml.safe_load(path.read_text(encoding="utf-8"))
            if not isinstance(config, dict):
                raise ApplyError("installed Hermes X API configuration is invalid")
            mcp_servers = config.get("mcp_servers")
            if not isinstance(mcp_servers, dict) or mcp_servers.get("xapi") != _XAPI_MCP:
                raise ApplyError("installed Hermes X API configuration is invalid")
    except ApplyError:
        raise
    except (OSError, TypeError, UnicodeError, ValueError, yaml.YAMLError):
        raise ApplyError("installed Hermes X API configuration is invalid") from None


def reconcile_onepassword_cli_permissions(
    data_root: Path,
    transaction: Transaction,
) -> None:
    """Keep the persisted 1Password CLI state private without following links."""

    path = data_root / ".config" / "op"
    try:
        metadata = path.lstat()
    except FileNotFoundError:
        return
    except OSError:
        raise ApplyError("could not secure 1Password CLI configuration") from None
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
        raise ApplyError("invalid 1Password CLI configuration directory")
    if stat.S_IMODE(metadata.st_mode) == 0o700:
        return

    descriptor: int | None = None
    try:
        transaction.snapshot(path)
        descriptor = os.open(
            path,
            os.O_RDONLY | os.O_CLOEXEC | os.O_DIRECTORY | os.O_NOFOLLOW,
        )
        opened = os.fstat(descriptor)
        current = path.lstat()
        if (
            not stat.S_ISDIR(opened.st_mode)
            or stat.S_ISLNK(current.st_mode)
            or (opened.st_dev, opened.st_ino) != (current.st_dev, current.st_ino)
        ):
            raise OSError
        os.fchmod(descriptor, 0o700)
        secured = os.fstat(descriptor)
        current = path.lstat()
        if (
            stat.S_IMODE(secured.st_mode) != 0o700
            or stat.S_ISLNK(current.st_mode)
            or (secured.st_dev, secured.st_ino) != (current.st_dev, current.st_ino)
        ):
            raise OSError
    except ApplyError:
        raise
    except (OSError, ValueError):
        raise ApplyError("could not secure 1Password CLI configuration") from None
    finally:
        if descriptor is not None:
            os.close(descriptor)


def reconcile_onepassword_configurations(
    manifest: BootstrapManifest,
    targets: Sequence[tuple[str, Path]],
    transaction: Transaction,
) -> None:
    """Merge managed onepassword settings into each Hermes config atomically."""

    if not manifest.onepassword_items:
        return

    try:
        for profile, target in targets:
            path = target / "config.yaml"
            try:
                metadata = path.lstat()
            except OSError:
                continue
            if (
                stat.S_ISLNK(metadata.st_mode)
                or not stat.S_ISREG(metadata.st_mode)
                or metadata.st_nlink != 1
            ):
                continue
            try:
                original_content = path.read_text(encoding="utf-8")
            except (OSError, UnicodeError):
                continue
            try:
                config = yaml.safe_load(original_content)
            except (OSError, UnicodeError, yaml.YAMLError):
                continue
            if not isinstance(config, dict):
                continue

            secrets = config.get("secrets")
            if secrets is None:
                secrets = {}
            if not isinstance(secrets, dict):
                continue
            onepassword = secrets.get("onepassword")
            if onepassword is None:
                onepassword = {}
            if not isinstance(onepassword, dict):
                continue
            existing_env = onepassword.get("env")
            if existing_env is None:
                existing_env = {}
            if not isinstance(existing_env, dict):
                continue
            retained_env = {
                key: value
                for key, value in existing_env.items()
                if key not in LEGACY_SLACK_KEYS
            }

            managed = build_onepassword_config(manifest, profile)
            if "secrets" not in config:
                content = (
                    original_content.rstrip("\n")
                    + "\n"
                    + yaml.safe_dump(
                        {"secrets": {"onepassword": managed}},
                        sort_keys=False,
                    )
                ).encode("utf-8")
                if path.read_bytes() == content:
                    continue
                transaction.snapshot(path)
                _atomic_write(path, content, stat.S_IMODE(metadata.st_mode))
                continue
            if onepassword == managed and existing_env == managed["env"]:
                continue
            merged_onepassword = dict(onepassword)
            merged_onepassword.update(managed)
            merged_onepassword["env"] = {
                **retained_env,
                **managed["env"],
            }
            merged_secrets = dict(secrets)
            merged_secrets["onepassword"] = merged_onepassword
            candidate = dict(config)
            candidate["secrets"] = merged_secrets
            content = yaml.safe_dump(candidate, sort_keys=False).encode("utf-8")
            if path.read_bytes() == content:
                continue
            transaction.snapshot(path)
            _atomic_write(path, content, stat.S_IMODE(metadata.st_mode))
    except (OSError, TypeError, UnicodeError, ValueError, yaml.YAMLError):
        raise ApplyError("could not reconcile Hermes 1Password configuration") from None
