"""Non-secret contracts for staged Hermes source distributions."""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from typing import NoReturn

import yaml

from .errors import ValidationError
from .git import StagedSource
from .manifest import _UniqueKeySafeLoader


_CHROME_MCP = {
    "url": "http://127.0.0.1:8765/mcp",
    "connect_timeout": 120,
}


def validate_chrome_mcp_sources(staged: Sequence[StagedSource]) -> None:
    """Require owned Chrome MCP configuration with the native browser disabled."""

    for source in staged:
        try:
            with (
                source.path / source.declaration.manifest_name
            ).open(encoding="utf-8") as handle:
                manifest = yaml.load(handle, Loader=_UniqueKeySafeLoader)
            with (source.path / "config.yaml").open(encoding="utf-8") as handle:
                config = yaml.load(handle, Loader=_UniqueKeySafeLoader)
        except (OSError, UnicodeError, yaml.YAMLError):
            _invalid(source)

        if not isinstance(manifest, Mapping):
            _invalid_ownership(source)
        distribution_owned = manifest.get("distribution_owned")
        if (
            not isinstance(distribution_owned, list)
            or "config.yaml" not in distribution_owned
        ):
            _invalid_ownership(source)
        if not isinstance(config, dict):
            _invalid(source)
        agent = config.get("agent")
        if not isinstance(agent, Mapping):
            _invalid(source)
        disabled_toolsets = agent.get("disabled_toolsets")
        if (
            not isinstance(disabled_toolsets, list)
            or any(not isinstance(toolset, str) for toolset in disabled_toolsets)
            or "browser" not in disabled_toolsets
        ):
            _invalid(source)
        mcp_servers = config.get("mcp_servers")
        if not isinstance(mcp_servers, dict):
            _invalid(source)
        chrome = mcp_servers.get("chrome")
        if (
            not isinstance(chrome, Mapping)
            or type(chrome.get("connect_timeout")) is not int
            or dict(chrome) != _CHROME_MCP
        ):
            _invalid(source)


def _invalid(source: StagedSource) -> NoReturn:
    name = source.declaration.name
    raise ValidationError(
        f"distribution {name!r} config.yaml has invalid Chrome MCP configuration"
    ) from None


def _invalid_ownership(source: StagedSource) -> NoReturn:
    name = source.declaration.name
    raise ValidationError(
        f"distribution {name!r} distribution_owned must include config.yaml"
    ) from None
