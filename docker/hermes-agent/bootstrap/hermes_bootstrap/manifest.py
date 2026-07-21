"""Strict parsing for the non-secret Hermes bootstrap manifest."""

from __future__ import annotations

import re
from collections.abc import Iterable, Mapping, Sequence
from pathlib import Path
from typing import Literal, TypeVar

import yaml

from .errors import ValidationError
from .models import (
    BootstrapManifest,
    DistributionSource,
    OnePasswordField,
    OnePasswordItem,
    SharedRepository,
)


_SCHEMA_VERSION = 1
_HERMES_DATA_ROOT = Path("/opt/data")
_NAME_PATTERN = re.compile(r"[a-z][a-z0-9-]*\Z")
_ITEM_KEY_PATTERN = re.compile(r"[a-z][a-z0-9_-]*\Z")
_GITHUB_SOURCE_PATTERN = re.compile(
    r"https://github\.com/[A-Za-z0-9](?:[A-Za-z0-9_.-]*[A-Za-z0-9])?"
    r"/[A-Za-z0-9](?:[A-Za-z0-9_.-]*[A-Za-z0-9])?\.git\Z"
)
_T = TypeVar("_T")


def load_manifest(path: Path) -> BootstrapManifest:
    """Load and validate a version-one manifest without reading secret values."""

    try:
        with path.open(encoding="utf-8") as handle:
            raw = yaml.safe_load(handle)
    except (OSError, yaml.YAMLError) as error:
        raise ValidationError(f"cannot load bootstrap manifest: {path}") from error

    manifest = _mapping(raw, "manifest")
    _keys(
        manifest,
        required={
            "schema_version",
            "data_root",
            "onepassword_items",
            "root_distribution",
            "profiles",
            "shared_repositories",
        },
        context="manifest",
    )

    schema_version = _integer(manifest["schema_version"], "manifest.schema_version")
    if schema_version != _SCHEMA_VERSION:
        _invalid("unsupported manifest schema version")

    data_root = _managed_path(manifest["data_root"], "manifest.data_root", None)
    if data_root != _HERMES_DATA_ROOT:
        _invalid("manifest.data_root must resolve to /opt/data")

    onepassword_items = _onepassword_items(manifest["onepassword_items"])
    root_distribution = _distribution(
        manifest["root_distribution"], "manifest.root_distribution", data_root
    )
    if root_distribution.name != "default" or root_distribution.target != data_root:
        _invalid("root distribution must be default at the data root")

    profiles = tuple(
        _distribution(value, f"manifest.profiles[{index}]", data_root)
        for index, value in enumerate(_sequence(manifest["profiles"], "manifest.profiles"))
    )
    repositories = tuple(
        _repository(value, f"manifest.shared_repositories[{index}]", data_root)
        for index, value in enumerate(
            _sequence(manifest["shared_repositories"], "manifest.shared_repositories")
        )
    )

    _unique((item.key for item in onepassword_items), "1Password item keys")
    _unique((item.item for item in onepassword_items), "1Password item names")
    _unique(
        (source.name for source in (root_distribution, *profiles, *repositories)),
        "managed source names",
    )
    _unique(
        (source.target for source in (root_distribution, *profiles, *repositories)),
        "managed targets",
    )
    _unique(
        (
            target
            for repository in repositories
            for target in (repository.target, repository.legacy_target)
            if target is not None
        ),
        "repository targets including legacy targets",
    )

    distribution_names = {root_distribution.name, *(profile.name for profile in profiles)}
    for repository in repositories:
        if repository.sync_owner is not None and repository.sync_owner not in distribution_names:
            _invalid(f"shared repository {repository.name!r} has an unknown sync_owner")

    return BootstrapManifest(
        schema_version=schema_version,
        data_root=data_root,
        onepassword_items=onepassword_items,
        root_distribution=root_distribution,
        profiles=profiles,
        shared_repositories=repositories,
    )


def _onepassword_items(value: object) -> tuple[OnePasswordItem, ...]:
    items: list[OnePasswordItem] = []
    for index, raw_item in enumerate(_sequence(value, "manifest.onepassword_items")):
        context = f"manifest.onepassword_items[{index}]"
        item = _mapping(raw_item, context)
        _keys(item, {"key", "account", "vault", "item", "fields"}, context)
        key = _text(item["key"], f"{context}.key")
        if not _ITEM_KEY_PATTERN.fullmatch(key):
            _invalid(f"{context}.key is invalid")

        fields: list[OnePasswordField] = []
        for field_index, raw_field in enumerate(_sequence(item["fields"], f"{context}.fields")):
            field_context = f"{context}.fields[{field_index}]"
            field = _mapping(raw_field, field_context)
            _keys(field, {"canonical_name", "labels"}, field_context)
            canonical_name = _text(field["canonical_name"], f"{field_context}.canonical_name")
            labels = tuple(
                _text(label, f"{field_context}.labels[{label_index}]")
                for label_index, label in enumerate(_sequence(field["labels"], f"{field_context}.labels"))
            )
            if not labels:
                _invalid(f"{field_context}.labels must not be empty")
            fields.append(OnePasswordField(canonical_name=canonical_name, labels=labels))
        if not fields:
            _invalid(f"{context}.fields must not be empty")
        _unique((field.canonical_name for field in fields), f"{context} field names")
        items.append(
            OnePasswordItem(
                key=key,
                account=_text(item["account"], f"{context}.account"),
                vault=_text(item["vault"], f"{context}.vault"),
                item=_text(item["item"], f"{context}.item"),
                fields=tuple(fields),
            )
        )
    if not items:
        _invalid("manifest.onepassword_items must not be empty")
    return tuple(items)


def _distribution(value: object, context: str, data_root: Path) -> DistributionSource:
    source = _mapping(value, context)
    _keys(source, {"name", "source", "ref", "target", "manifest"}, context)
    name = _name(source["name"], f"{context}.name")
    return DistributionSource(
        name=name,
        source=_github_source(source["source"], f"{context}.source"),
        ref=_ref(source["ref"], f"{context}.ref"),
        target=_managed_path(source["target"], f"{context}.target", data_root),
        manifest_name=_manifest_name(source["manifest"], f"{context}.manifest"),
    )


def _repository(value: object, context: str, data_root: Path) -> SharedRepository:
    repository = _mapping(value, context)
    _keys(
        repository,
        {"name", "source", "ref", "target", "mode"},
        context,
        optional={"sync_owner", "legacy_target"},
    )
    name = _name(repository["name"], f"{context}.name")
    mode = _text(repository["mode"], f"{context}.mode")
    if mode not in {"read-only", "read-write"}:
        _invalid(f"{context}.mode is unsupported")

    sync_owner: str | None = None
    if "sync_owner" in repository and repository["sync_owner"] is not None:
        sync_owner = _name(repository["sync_owner"], f"{context}.sync_owner")
    if mode == "read-write" and sync_owner is None:
        _invalid(f"{context}.sync_owner is required for read-write repositories")

    legacy_target = None
    if "legacy_target" in repository and repository["legacy_target"] is not None:
        legacy_target = _managed_path(
            repository["legacy_target"], f"{context}.legacy_target", data_root
        )

    return SharedRepository(
        name=name,
        source=_github_source(repository["source"], f"{context}.source"),
        ref=_ref(repository["ref"], f"{context}.ref"),
        target=_managed_path(repository["target"], f"{context}.target", data_root),
        mode=mode,
        sync_owner=sync_owner,
        legacy_target=legacy_target,
    )


def _mapping(value: object, context: str) -> Mapping[str, object]:
    if not isinstance(value, Mapping) or not all(isinstance(key, str) for key in value):
        _invalid(f"{context} must be a mapping")
    return value


def _sequence(value: object, context: str) -> Sequence[object]:
    if not isinstance(value, list):
        _invalid(f"{context} must be a sequence")
    return value


def _keys(
    value: Mapping[str, object],
    required: set[str],
    context: str,
    optional: set[str] | None = None,
) -> None:
    allowed = required | (optional or set())
    missing = required - value.keys()
    unknown = value.keys() - allowed
    if missing or unknown:
        _invalid(f"{context} has unsupported or missing keys")


def _integer(value: object, context: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool):
        _invalid(f"{context} must be an integer")
    return value


def _text(value: object, context: str) -> str:
    if not isinstance(value, str) or not value or value != value.strip():
        _invalid(f"{context} must be a non-empty trimmed string")
    return value


def _name(value: object, context: str) -> str:
    name = _text(value, context)
    if not _NAME_PATTERN.fullmatch(name):
        _invalid(f"{context} is invalid")
    return name


def _github_source(value: object, context: str) -> str:
    source = _text(value, context)
    if not _GITHUB_SOURCE_PATTERN.fullmatch(source):
        _invalid(f"{context} must be a GitHub HTTPS .git URL")
    return source


def _ref(value: object, context: str) -> str:
    ref = _text(value, context)
    invalid = (
        ref.startswith(("-", "/"))
        or ref.endswith((".", "/", ".lock"))
        or ".." in ref
        or "@{" in ref
        or "//" in ref
        or any(character in ref for character in " ~^:?*[\\")
        or any(ord(character) < 32 or ord(character) == 127 for character in ref)
    )
    if invalid:
        _invalid(f"{context} is not a valid Git ref")
    return ref


def _manifest_name(value: object, context: str) -> str:
    manifest_name = _text(value, context)
    path = Path(manifest_name)
    if path.is_absolute() or path.name != manifest_name or manifest_name in {".", ".."}:
        _invalid(f"{context} must be a single relative filename")
    return manifest_name


def _managed_path(value: object, context: str, data_root: Path | None) -> Path:
    text = _text(value, context)
    path = Path(text)
    if not path.is_absolute():
        _invalid(f"{context} must be absolute")
    resolved = path.resolve(strict=False)
    if data_root is not None:
        try:
            resolved.relative_to(data_root)
        except ValueError:
            _invalid(f"{context} must resolve beneath the data root")
    return resolved


def _unique(values: Iterable[_T], context: str) -> None:
    seen: set[_T] = set()
    for value in values:
        if value in seen:
            _invalid(f"{context} must be unique")
        seen.add(value)


def _invalid(message: str) -> None:
    raise ValidationError(message)
