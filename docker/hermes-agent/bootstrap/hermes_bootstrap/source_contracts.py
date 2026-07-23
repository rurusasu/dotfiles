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
    """Require the canonical Chrome MCP entry in every staged distribution."""

    for source in staged:
        try:
            with (source.path / "config.yaml").open(encoding="utf-8") as handle:
                config = yaml.load(handle, Loader=_UniqueKeySafeLoader)
        except (OSError, UnicodeError, yaml.YAMLError):
            _invalid(source)

        if not isinstance(config, Mapping):
            _invalid(source)
        mcp_servers = config.get("mcp_servers")
        if not isinstance(mcp_servers, Mapping):
            _invalid(source)
        chrome = mcp_servers.get("chrome")
        if not isinstance(chrome, Mapping) or dict(chrome) != _CHROME_MCP:
            _invalid(source)


def _invalid(source: StagedSource) -> NoReturn:
    name = source.declaration.name
    raise ValidationError(
        f"distribution {name!r} config.yaml has invalid Chrome MCP configuration"
    ) from None
