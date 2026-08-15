"""Transactional Hindsight configuration for every Hermes profile."""

from __future__ import annotations

import json
import os
import stat
from collections.abc import Sequence
from pathlib import Path

import yaml

from .distributions import _atomic_write
from .errors import ApplyError, ValidationError
from .transaction import Transaction


HINDSIGHT_RETAIN_MISSION: str = (
    "Retain durable preferences, decisions, corrections, entities, relationships, "
    "and temporal facts. Never extract credentials, tokens, private keys, "
    "authentication material, or transient logs as memories."
)

_APPLY_ERROR = "could not reconcile Hermes Hindsight configuration"
_VALIDATION_ERROR = "installed Hermes Hindsight configuration is invalid"


def build_hindsight_config() -> dict[str, object]:
    """Return the canonical non-secret provider configuration."""

    return {
        "mode": "local_external",
        "api_url": "http://hindsight:8888",
        "bank_id": "hermes",
        "bank_id_template": "hermes-{profile}",
        "bank_retain_mission": HINDSIGHT_RETAIN_MISSION,
        "memory_mode": "hybrid",
        "auto_recall": True,
        "recall_sync": False,
        "recall_types": "observation",
        "recall_budget": "mid",
        "auto_retain": True,
        "retain_async": True,
        "retain_every_n_turns": 1,
        "retain_source": "hermes",
    }


def install_hindsight_configurations(
    targets: Sequence[tuple[str, Path]],
    transaction: Transaction,
) -> None:
    """Enable Hindsight and atomically reconcile each profile config."""

    try:
        for _profile, target in targets:
            _require_real_directory_chain(target)
            _reconcile_hermes_config(target / "config.yaml", transaction)
            _reconcile_hindsight_config(target / "hindsight", transaction)
    except (
        ApplyError,
        OSError,
        TypeError,
        UnicodeError,
        ValueError,
        yaml.YAMLError,
    ):
        raise ApplyError(_APPLY_ERROR) from None


def validate_hindsight_installation(
    targets: Sequence[tuple[str, Path]],
) -> None:
    """Require the canonical provider state for every target."""

    try:
        expected = build_hindsight_config()
        for _profile, target in targets:
            _require_real_directory_chain(target)
            config_path = target / "config.yaml"
            config_metadata, config = _load_yaml_mapping(config_path)
            if stat.S_IMODE(config_metadata.st_mode) != 0o600:
                raise ValueError
            memory = config.get("memory")
            if not isinstance(memory, dict) or memory.get("provider") != "hindsight":
                raise ValueError

            directory = target / "hindsight"
            directory_metadata = _require_directory(directory)
            if stat.S_IMODE(directory_metadata.st_mode) != 0o700:
                raise ValueError

            json_path = directory / "config.json"
            json_metadata, installed = _load_json_mapping(json_path)
            if stat.S_IMODE(json_metadata.st_mode) != 0o600:
                raise ValueError
            if any(installed.get(key) != value for key, value in expected.items()):
                raise ValueError
    except (OSError, TypeError, UnicodeError, ValueError, yaml.YAMLError):
        raise ValidationError(_VALIDATION_ERROR) from None


def _reconcile_hermes_config(path: Path, transaction: Transaction) -> None:
    metadata, config = _load_yaml_mapping(path)
    memory = config.get("memory")
    if memory is None:
        memory = {}
    if not isinstance(memory, dict):
        raise ValueError

    merged_memory = dict(memory)
    merged_memory["provider"] = "hindsight"
    if (
        merged_memory == memory
        and stat.S_IMODE(metadata.st_mode) == 0o600
    ):
        return
    candidate = dict(config)
    candidate["memory"] = merged_memory
    content = yaml.safe_dump(candidate, sort_keys=False).encode("utf-8")
    if path.read_bytes() == content and stat.S_IMODE(metadata.st_mode) == 0o600:
        return
    transaction.snapshot(path)
    _atomic_write(path, content, 0o600)


def _reconcile_hindsight_config(
    directory: Path,
    transaction: Transaction,
) -> None:
    if os.path.lexists(directory):
        metadata = _require_directory(directory)
        if stat.S_IMODE(metadata.st_mode) != 0o700:
            transaction.snapshot(directory)
            directory.chmod(0o700)
    elif not transaction.reserve_directory(directory):
        raise ValueError

    path = directory / "config.json"
    if os.path.lexists(path):
        metadata, current = _load_json_mapping(path)
        original = path.read_bytes()
    else:
        metadata = None
        current = {}
        original = None

    candidate = dict(current)
    candidate.update(build_hindsight_config())
    content = (
        json.dumps(
            candidate,
            allow_nan=False,
            ensure_ascii=False,
            indent=2,
            sort_keys=True,
        )
        + "\n"
    ).encode("utf-8")
    if (
        original == content
        and metadata is not None
        and stat.S_IMODE(metadata.st_mode) == 0o600
    ):
        return
    transaction.snapshot(path)
    _atomic_write(path, content, 0o600)


def _load_yaml_mapping(path: Path) -> tuple[os.stat_result, dict[object, object]]:
    metadata = _require_regular_file(path)
    value = yaml.safe_load(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError
    return metadata, value


def _load_json_mapping(path: Path) -> tuple[os.stat_result, dict[str, object]]:
    metadata = _require_regular_file(path)
    value = json.loads(
        path.read_text(encoding="utf-8"),
        parse_constant=_reject_json_constant,
    )
    if not isinstance(value, dict):
        raise ValueError
    return metadata, value


def _reject_json_constant(value: str) -> object:
    del value
    raise ValueError


def _require_regular_file(path: Path) -> os.stat_result:
    metadata = path.lstat()
    if (
        stat.S_ISLNK(metadata.st_mode)
        or not stat.S_ISREG(metadata.st_mode)
        or metadata.st_nlink != 1
    ):
        raise ValueError
    return metadata


def _require_directory(path: Path) -> os.stat_result:
    metadata = path.lstat()
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
        raise ValueError
    return metadata


def _require_real_directory_chain(path: Path) -> None:
    if not path.is_absolute():
        raise ValueError
    current = path
    while True:
        _require_directory(current)
        if current.parent == current:
            return
        current = current.parent
