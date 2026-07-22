"""Immutable domain objects parsed from the bootstrap manifest."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Literal


@dataclass(frozen=True)
class OnePasswordField:
    canonical_name: str
    labels: tuple[str, ...]


@dataclass(frozen=True)
class OnePasswordItem:
    key: str
    account: str
    vault: str
    item: str
    fields: tuple[OnePasswordField, ...]


@dataclass(frozen=True)
class DistributionSource:
    name: str
    source: str
    ref: str
    target: Path
    manifest_name: str


@dataclass(frozen=True)
class SharedRepository:
    name: str
    source: str
    ref: str
    target: Path
    mode: Literal["read-only", "read-write"]
    sync_owner: str | None
    legacy_target: Path | None


@dataclass(frozen=True)
class BootstrapManifest:
    schema_version: int
    data_root: Path
    onepassword_items: tuple[OnePasswordItem, ...]
    root_distribution: DistributionSource
    profiles: tuple[DistributionSource, ...]
    shared_repositories: tuple[SharedRepository, ...]
