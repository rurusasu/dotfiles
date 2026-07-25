"""Non-secret contracts for staged Hermes source distributions."""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from typing import NoReturn

import yaml

from .errors import ValidationError
from .git import StagedSource


_CHROME_MCP = {
    "url": "http://browser-mcp:8080/mcp",
    "connect_timeout": 120,
}
_XAPI_MCP = {
    "url": "http://xapi-mcp:8080/mcp",
    "connect_timeout": 300,
}


class _UniqueKeySafeLoader(yaml.SafeLoader):
    """Safe YAML loader that rejects duplicate keys in every mapping."""

    def construct_mapping(
        self, node: yaml.MappingNode, deep: bool = False
    ) -> dict[object, object]:
        self.flatten_mapping(node)
        mapping: dict[object, object] = {}
        for key_node, value_node in node.value:
            key = self.construct_object(key_node, deep=deep)
            try:
                duplicate = key in mapping
            except TypeError as error:
                raise yaml.constructor.ConstructorError(
                    "while constructing a mapping",
                    node.start_mark,
                    "found unacceptable key",
                    key_node.start_mark,
                ) from error
            if duplicate:
                raise yaml.constructor.ConstructorError(
                    "while constructing a mapping",
                    node.start_mark,
                    "found duplicate key",
                    key_node.start_mark,
                )
            mapping[key] = self.construct_object(value_node, deep=deep)
        return mapping


def validate_chrome_mcp_sources(staged: Sequence[StagedSource]) -> None:
    """Require Chrome MCP and install the canonical X API MCP entry."""

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
        if not isinstance(config, Mapping):
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
        _install_xapi_mcp(source, config, mcp_servers)


def _install_xapi_mcp(
    source: StagedSource,
    config: Mapping[object, object],
    mcp_servers: dict[object, object],
) -> None:
    xapi = mcp_servers.get("xapi")
    if (
        isinstance(xapi, Mapping)
        and type(xapi.get("connect_timeout")) is int
        and dict(xapi) == _XAPI_MCP
    ):
        return

    if not isinstance(config, dict):
        _invalid_xapi(source)
    mcp_servers["xapi"] = dict(_XAPI_MCP)
    try:
        (source.path / "config.yaml").write_text(
            yaml.safe_dump(config, sort_keys=False), encoding="utf-8"
        )
    except (OSError, UnicodeError):
        _invalid_xapi(source)


def _invalid(source: StagedSource) -> NoReturn:
    name = source.declaration.name
    raise ValidationError(
        f"distribution {name!r} config.yaml has invalid Chrome MCP configuration"
    ) from None


def _invalid_xapi(source: StagedSource) -> NoReturn:
    name = source.declaration.name
    raise ValidationError(
        f"distribution {name!r} config.yaml has invalid X API MCP configuration"
    ) from None


def _invalid_ownership(source: StagedSource) -> NoReturn:
    name = source.declaration.name
    raise ValidationError(
        f"distribution {name!r} distribution_owned must include config.yaml"
    ) from None
