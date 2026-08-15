"""Transactional Hindsight configuration for every Hermes profile."""

from __future__ import annotations

import json
import os
import stat
import uuid
from collections.abc import Sequence
from pathlib import Path

import yaml

from .distributions import _atomic_write as _atomic_write_path
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
            with transaction.bind_reserved_directory(target) as reserved:
                if reserved is None:
                    _reconcile_hermes_config(
                        target / "config.yaml",
                        transaction,
                    )
                    _reconcile_hindsight_config(
                        target / "hindsight",
                        transaction,
                    )
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


def _reconcile_reserved_configuration(directory: int) -> None:
    metadata, original, config = _load_yaml_mapping_at(
        directory,
        "config.yaml",
    )
    memory = config.get("memory")
    if memory is None:
        memory = {}
    if not isinstance(memory, dict):
        raise ValueError
    merged_memory = dict(memory)
    merged_memory["provider"] = "hindsight"
    if not (
        merged_memory == memory
        and stat.S_IMODE(metadata.st_mode) == 0o600
    ):
        candidate = dict(config)
        candidate["memory"] = merged_memory
        content = yaml.safe_dump(candidate, sort_keys=False).encode("utf-8")
        if original != content or stat.S_IMODE(metadata.st_mode) != 0o600:
            _atomic_write((directory, "config.yaml"), content, 0o600)

    hindsight = _open_or_create_directory_at(directory, "hindsight", 0o700)
    try:
        try:
            json_metadata, json_original, current = _load_json_mapping_at(
                hindsight,
                "config.json",
            )
        except FileNotFoundError:
            json_metadata = None
            json_original = None
            current = {}
        candidate_json = dict(current)
        candidate_json.update(build_hindsight_config())
        json_content = (
            json.dumps(
                candidate_json,
                allow_nan=False,
                ensure_ascii=False,
                indent=2,
                sort_keys=True,
            )
            + "\n"
        ).encode("utf-8")
        if not (
            json_original == json_content
            and json_metadata is not None
            and stat.S_IMODE(json_metadata.st_mode) == 0o600
        ):
            _atomic_write(
                (hindsight, "config.json"),
                json_content,
                0o600,
            )
    finally:
        os.close(hindsight)


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
        raise ValueError
    return metadata, content, value


def _load_json_mapping_at(
    parent: int,
    name: str,
) -> tuple[os.stat_result, bytes, dict[str, object]]:
    metadata, content = _read_regular_file_at(parent, name)
    value = json.loads(
        content.decode("utf-8"),
        parse_constant=_reject_json_constant,
    )
    if not isinstance(value, dict):
        raise ValueError
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


def _open_or_create_directory_at(
    parent: int,
    name: str,
    mode: int,
) -> int:
    _require_child_name(name)
    created = False
    try:
        os.mkdir(name, mode=mode, dir_fd=parent)
        created = True
    except FileExistsError:
        pass
    before = os.stat(name, dir_fd=parent, follow_symlinks=False)
    if stat.S_ISLNK(before.st_mode) or not stat.S_ISDIR(before.st_mode):
        raise ValueError
    descriptor: int | None = None
    try:
        descriptor = os.open(
            name,
            os.O_RDONLY
            | os.O_CLOEXEC
            | getattr(os, "O_DIRECTORY", 0)
            | getattr(os, "O_NOFOLLOW", 0),
            dir_fd=parent,
        )
        opened = os.fstat(descriptor)
        if (
            not stat.S_ISDIR(opened.st_mode)
            or (before.st_dev, before.st_ino)
            != (opened.st_dev, opened.st_ino)
        ):
            raise ValueError
        if stat.S_IMODE(opened.st_mode) != mode:
            os.fchmod(descriptor, mode)
            created = True
        if created:
            os.fsync(descriptor)
            os.fsync(parent)
        result = descriptor
        descriptor = None
        return result
    finally:
        if descriptor is not None:
            os.close(descriptor)


def _require_child_name(name: str) -> None:
    if not name or name in {".", ".."} or "/" in name or "\\" in name:
        raise ValueError


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
