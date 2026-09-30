"""Transactional Hermes context-engine configuration."""

from __future__ import annotations

import os
import stat
import uuid
from collections.abc import Sequence
from pathlib import Path

import yaml

from .distributions import _atomic_write as _atomic_write_path
from .errors import ApplyError, ValidationError
from .transaction import Transaction

CONTEXT_ENGINE_NAME = "lcm"
CONTEXT_PLUGIN_NAME = "hermes-lcm"

_APPLY_ERROR = "could not reconcile Hermes context engine configuration"
_VALIDATION_ERROR = "installed Hermes context engine configuration is invalid"


def install_context_engine_configurations(
    targets: Sequence[tuple[str, Path]],
    transaction: Transaction,
) -> None:
    """Enable the LCM engine and plugin in every managed Hermes config."""

    try:
        for _profile, target in targets:
            _require_real_directory_chain(target)
            with transaction.bind_reserved_directory(target) as reserved:
                if reserved is None:
                    _reconcile_config(target / "config.yaml", transaction)
                else:
                    _reconcile_reserved_configuration(reserved)
    except (
        ApplyError,
        OSError,
        TypeError,
        UnicodeError,
        ValueError,
        yaml.YAMLError,
    ):
        raise ApplyError(_APPLY_ERROR) from None


def validate_context_engine_installation(
    targets: Sequence[tuple[str, Path]],
) -> None:
    """Require LCM activation without inspecting memory-provider settings."""

    try:
        for _profile, target in targets:
            _require_real_directory_chain(target)
            metadata, config = _load_yaml_mapping(target / "config.yaml")
            if stat.S_IMODE(metadata.st_mode) != 0o600:
                raise ValueError

            context = config.get("context")
            if (
                not isinstance(context, dict)
                or context.get("engine") != CONTEXT_ENGINE_NAME
            ):
                raise ValueError

            plugins = config.get("plugins")
            if not isinstance(plugins, dict):
                raise TypeError
            enabled = plugins.get("enabled")
            if not isinstance(enabled, list) or CONTEXT_PLUGIN_NAME not in enabled:
                raise ValueError
            disabled = plugins.get("disabled", [])
            if not isinstance(disabled, list) or CONTEXT_PLUGIN_NAME in disabled:
                raise ValueError
    except (OSError, TypeError, UnicodeError, ValueError, yaml.YAMLError):
        raise ValidationError(_VALIDATION_ERROR) from None


def _reconcile_config(path: Path, transaction: Transaction) -> None:
    metadata, original, config = _load_yaml_mapping_with_content(path)

    context = config.get("context")
    if context is None:
        context = {}
    if not isinstance(context, dict):
        raise TypeError
    merged_context = dict(context)
    merged_context["engine"] = CONTEXT_ENGINE_NAME

    plugins = config.get("plugins")
    if plugins is None:
        plugins = {}
    if not isinstance(plugins, dict):
        raise TypeError
    merged_plugins = dict(plugins)

    if "enabled" not in plugins:
        enabled: list[object] = []
    else:
        enabled_value = plugins["enabled"]
        if not isinstance(enabled_value, list) or any(
            not isinstance(item, str) for item in enabled_value
        ):
            raise ValueError
        enabled = list(enabled_value)
    if CONTEXT_PLUGIN_NAME not in enabled:
        enabled.append(CONTEXT_PLUGIN_NAME)
    else:
        enabled = [
            item
            for index, item in enumerate(enabled)
            if item != CONTEXT_PLUGIN_NAME or CONTEXT_PLUGIN_NAME not in enabled[:index]
        ]
    merged_plugins["enabled"] = enabled

    if "disabled" in plugins:
        disabled_value = plugins["disabled"]
        if not isinstance(disabled_value, list) or any(
            not isinstance(item, str) for item in disabled_value
        ):
            raise ValueError
        merged_plugins["disabled"] = [
            item for item in disabled_value if item != CONTEXT_PLUGIN_NAME
        ]

    candidate = dict(config)
    candidate["context"] = merged_context
    candidate["plugins"] = merged_plugins
    content = yaml.safe_dump(candidate, sort_keys=False).encode("utf-8")
    if original == content and stat.S_IMODE(metadata.st_mode) == 0o600:
        return

    transaction.snapshot(path)
    _atomic_write(path, content, 0o600)


def _reconcile_reserved_configuration(directory: int) -> None:
    metadata, original, config = _load_yaml_mapping_at(directory, "config.yaml")

    context = config.get("context")
    if context is None:
        context = {}
    if not isinstance(context, dict):
        raise TypeError
    merged_context = dict(context)
    merged_context["engine"] = CONTEXT_ENGINE_NAME

    plugins = config.get("plugins")
    if plugins is None:
        plugins = {}
    if not isinstance(plugins, dict):
        raise TypeError
    merged_plugins = dict(plugins)

    enabled_value = plugins.get("enabled", [])
    if not isinstance(enabled_value, list) or any(
        not isinstance(item, str) for item in enabled_value
    ):
        raise ValueError
    enabled = list(enabled_value)
    if CONTEXT_PLUGIN_NAME not in enabled:
        enabled.append(CONTEXT_PLUGIN_NAME)
    else:
        enabled = [
            item
            for index, item in enumerate(enabled)
            if item != CONTEXT_PLUGIN_NAME or CONTEXT_PLUGIN_NAME not in enabled[:index]
        ]
    merged_plugins["enabled"] = enabled

    if "disabled" in plugins:
        disabled_value = plugins["disabled"]
        if not isinstance(disabled_value, list) or any(
            not isinstance(item, str) for item in disabled_value
        ):
            raise ValueError
        merged_plugins["disabled"] = [
            item for item in disabled_value if item != CONTEXT_PLUGIN_NAME
        ]

    candidate = dict(config)
    candidate["context"] = merged_context
    candidate["plugins"] = merged_plugins
    content = yaml.safe_dump(candidate, sort_keys=False).encode("utf-8")
    if original == content and stat.S_IMODE(metadata.st_mode) == 0o600:
        return
    _atomic_write((directory, "config.yaml"), content, 0o600)


def _atomic_write(
    destination: Path | tuple[int, str],
    content: bytes,
    mode: int,
) -> None:
    if isinstance(destination, Path):
        _atomic_write_path(destination, content, mode)
        return
    parent, name = destination
    _atomic_write_at(parent, name, content, mode)


def _atomic_write_at(
    parent: int,
    name: str,
    content: bytes,
    mode: int,
) -> None:
    _require_child_name(name)
    temporary = f".{name}.hermes-bootstrap-{uuid.uuid4()}"
    descriptor: int | None = None
    try:
        descriptor = os.open(
            temporary,
            os.O_WRONLY
            | os.O_CREAT
            | os.O_EXCL
            | os.O_CLOEXEC
            | getattr(os, "O_NOFOLLOW", 0),
            0o600,
            dir_fd=parent,
        )
        remaining = memoryview(content)
        while remaining:
            written = os.write(descriptor, remaining)
            if written <= 0:
                raise OSError
            remaining = remaining[written:]
        os.fchmod(descriptor, mode)
        os.fsync(descriptor)
        os.close(descriptor)
        descriptor = None
        os.replace(
            temporary,
            name,
            src_dir_fd=parent,
            dst_dir_fd=parent,
        )
        os.fsync(parent)
        temporary = ""
    finally:
        if descriptor is not None:
            os.close(descriptor)
        if temporary:
            try:
                os.unlink(temporary, dir_fd=parent)
            except FileNotFoundError:
                pass


def _load_yaml_mapping_at(
    parent: int,
    name: str,
) -> tuple[os.stat_result, bytes, dict[object, object]]:
    metadata, content = _read_regular_file_at(parent, name)
    value = yaml.safe_load(content.decode("utf-8"))
    if not isinstance(value, dict):
        raise TypeError
    return metadata, content, value


def _read_regular_file_at(
    parent: int,
    name: str,
) -> tuple[os.stat_result, bytes]:
    _require_child_name(name)
    before = os.stat(name, dir_fd=parent, follow_symlinks=False)
    if (
        stat.S_ISLNK(before.st_mode)
        or not stat.S_ISREG(before.st_mode)
        or before.st_nlink != 1
    ):
        raise ValueError
    descriptor: int | None = None
    try:
        descriptor = os.open(
            name,
            os.O_RDONLY | os.O_CLOEXEC | getattr(os, "O_NOFOLLOW", 0),
            dir_fd=parent,
        )
        opened = os.fstat(descriptor)
        after = os.stat(name, dir_fd=parent, follow_symlinks=False)
        identities = {
            (before.st_dev, before.st_ino),
            (opened.st_dev, opened.st_ino),
            (after.st_dev, after.st_ino),
        }
        if (
            len(identities) != 1
            or not stat.S_ISREG(opened.st_mode)
            or opened.st_nlink != 1
            or after.st_nlink != 1
        ):
            raise ValueError
        chunks: list[bytes] = []
        while chunk := os.read(descriptor, 65536):
            chunks.append(chunk)
        return opened, b"".join(chunks)
    finally:
        if descriptor is not None:
            os.close(descriptor)


def _require_child_name(name: str) -> None:
    if not name or name in {".", ".."} or "/" in name or "\\" in name:
        raise ValueError


def _load_yaml_mapping_with_content(
    path: Path,
) -> tuple[os.stat_result, bytes, dict[object, object]]:
    metadata = _require_regular_file(path)
    content = path.read_bytes()
    value = yaml.safe_load(content.decode("utf-8"))
    if not isinstance(value, dict):
        raise TypeError
    return metadata, content, value


def _load_yaml_mapping(path: Path) -> tuple[os.stat_result, dict[object, object]]:
    metadata, _content, value = _load_yaml_mapping_with_content(path)
    return metadata, value


def _require_regular_file(path: Path) -> os.stat_result:
    metadata = path.lstat()
    if (
        stat.S_ISLNK(metadata.st_mode)
        or not stat.S_ISREG(metadata.st_mode)
        or metadata.st_nlink != 1
    ):
        raise ValueError
    return metadata


def _require_real_directory_chain(path: Path) -> None:
    if not path.is_absolute():
        raise ValueError
    current = path
    while True:
        metadata = current.lstat()
        if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
            raise ValueError
        if current.parent == current:
            return
        current = current.parent
