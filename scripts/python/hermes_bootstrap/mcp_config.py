"""Shared I/O for transactionally merging managed MCP server entries."""

from __future__ import annotations

import os
import stat
from collections.abc import Sequence
from pathlib import Path

import yaml

from .transaction import Transaction


def load_managed_config(
    path: Path,
    *,
    create_servers: bool = False,
) -> tuple[os.stat_result, dict[object, object], dict[object, object]] | None:
    """Read a single regular config file without following links."""
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
        servers = config.get("mcp_servers")
        if servers is None and create_servers:
            servers = {}
        if not isinstance(servers, dict):
            return None
        return metadata, config, servers
    except (OSError, UnicodeError, yaml.YAMLError):
        return None


def install_mcp_configurations(
    targets: Sequence[Path],
    name: str,
    configuration: dict[str, object],
    transaction: Transaction,
    *,
    skip_invalid: bool,
    create_servers: bool = False,
) -> None:
    """Merge one server, retaining each caller's invalid-config policy."""
    # Distributions also imports Gmail's config predicate; avoid an import cycle.
    from .distributions import _atomic_write

    for target in targets:
        path = target / "config.yaml"
        candidate = load_managed_config(path, create_servers=create_servers)
        if candidate is None:
            if not skip_invalid:
                raise ValueError("invalid managed MCP configuration")
            # Credential installers defer replacement-race errors to final validation.
            continue
        metadata, config, servers = candidate
        if servers.get(name) == configuration:
            continue
        # YAML aliases may share this mapping with an unmanaged section.
        candidate = {**config, "mcp_servers": {**servers, name: configuration}}
        transaction.snapshot(path)
        _atomic_write(
            path,
            yaml.safe_dump(candidate, sort_keys=False).encode("utf-8"),
            stat.S_IMODE(metadata.st_mode),
        )
