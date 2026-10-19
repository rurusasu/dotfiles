"""Build allowlisted local profile projections for publication."""

from __future__ import annotations

import os
import re
import shutil
import stat
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Literal

import yaml

from . import distributions
from .errors import RepositoryError
from .models import BootstrapManifest, DistributionSource


ProfileMode = Literal[0o644, 0o755]

_DECLARATIVE_KEYS = (
    "name", "version", "description", "hermes_requires", "author",
    "license", "env_requires", "distribution_owned",
)
_RUNTIME_KEYS = frozenset({"source", "installed_at"})
_PROFILE_NAME = re.compile(r"[a-z][a-z0-9-]*\Z")
_PORTABLE_COMPONENT = re.compile(r"[A-Za-z0-9._-]+\Z")
_PRIVATE_KEY_HEADERS = (
    b"-----BEGIN PRIVATE KEY-----",
    b"-----BEGIN ENCRYPTED PRIVATE KEY-----",
    b"-----BEGIN RSA PRIVATE KEY-----",
    b"-----BEGIN EC PRIVATE KEY-----",
    b"-----BEGIN DSA PRIVATE KEY-----",
    b"-----BEGIN OPENSSH PRIVATE KEY-----",
)
_SECRET_PATTERNS = (
    re.compile(
        rb"(?<![A-Za-z0-9_])(?:gh[pousr]_[A-Za-z0-9]{20,}"
        rb"|github_pat_[A-Za-z0-9_]{20,})(?![A-Za-z0-9_])"
    ),
    re.compile(
        rb"(?<![A-Za-z0-9_])(?:xoxb|xoxp|xoxa|xoxr|xoxs|xapp)-"
        rb"[A-Za-z0-9-]+(?![A-Za-z0-9_-])"
    ),
    re.compile(
        rb"(?<![A-Za-z0-9])(?:sk-|hf_|xai-)[A-Za-z0-9_-]{20,}"
        rb"(?![A-Za-z0-9])"
    ),
    re.compile(rb"(?<![A-Za-z0-9])1//[A-Za-z0-9._-]{20,}(?![A-Za-z0-9])"),
    re.compile(
        rb"(?<![A-Za-z0-9])eyJ[A-Za-z0-9_-]{10,}\."
        rb"[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}(?![A-Za-z0-9_-])"
    ),
    re.compile(rb"(?<![A-Za-z0-9])(?:AKIA|ASIA)[A-Z0-9]{16}(?![A-Za-z0-9])"),
)
_GIT_CONTROL_COMPONENTS = frozenset({".git", ".gitignore", ".gitattributes", ".gitmodules"})
_RESERVED_COMPONENTS = frozenset(
    {
        ".bootstrap", ".git", "auth", "auth.json", "browser", "browser_data",
        "cache", "caches", "credential", "credentials", "home", "locks", "logs",
        "memories", "oauth", "plans", "runtime", "sessions", "token", "tokens",
        "workspace",
    }
)
_CREDENTIAL_STEMS = frozenset(
    {
        "api-key", "apikey", "auth", "certificate", "client-secret", "credential",
        "credentials", "password", "passwd", "private-key", "refresh-token",
        "secret", "secrets", "token", "tokens",
    }
)
_ENV_TEMPLATE = PurePosixPath(".env.template")
_INSTALLED_ENV_EXAMPLE = PurePosixPath(".env.EXAMPLE")


@dataclass(frozen=True)
class SnapshotEntry:
    path: PurePosixPath
    mode: ProfileMode


@dataclass(frozen=True)
class ProfileSnapshot:
    declaration: DistributionSource
    root: Path
    manifest_bytes: bytes
    gitignore_bytes: bytes
    entries: tuple[SnapshotEntry, ...]


@dataclass(frozen=True)
class ProfileSnapshotError(RepositoryError):
    """A redacted, immutable local-profile preflight failure."""

    profile: str
    category: str

    def __post_init__(self) -> None:
        RepositoryError.__init__(self, f"profile snapshot rejected ({self.category})")


def prepare_profile_snapshots(
    manifest: BootstrapManifest, scratch_root: Path
) -> tuple[ProfileSnapshot, ...]:
    """Copy installed profiles into caller-owned private scratch space.

    Validate source paths before reading them. The caller owns the resulting
    scratch trees and removes them after publication or dry-run completion.
    """

    _require_private_scratch(scratch_root)
    snapshots: list[ProfileSnapshot] = []
    try:
        for declaration in manifest.profiles:
            try:
                try:
                    _validate_profile_name(declaration.name)
                except ValueError:
                    raise ProfileSnapshotError(
                        declaration.name, "invalid_profile_name"
                    ) from None
                if declaration.target != manifest.data_root / "profiles" / declaration.name:
                    raise ProfileSnapshotError(declaration.name, "invalid_profile_target")
                if not _require_directory_chain(declaration.target, allow_missing=True):
                    raise ProfileSnapshotError(declaration.name, "missing_profile")
                if scratch_root.is_relative_to(declaration.target):
                    raise ValueError("scratch is inside the source profile")
                snapshots.append(_prepare_one(declaration, scratch_root))
            except ProfileSnapshotError:
                raise
            except Exception as error:
                raise ProfileSnapshotError(declaration.name, _category(error)) from None
    except ProfileSnapshotError:
        cleanup_profile: str | None = None
        for snapshot in reversed(snapshots):
            try:
                shutil.rmtree(snapshot.root)
            except OSError:
                cleanup_profile = cleanup_profile or snapshot.declaration.name
        if cleanup_profile is not None:
            raise ProfileSnapshotError(cleanup_profile, "cleanup_failed") from None
        raise
    return tuple(snapshots)


def _prepare_one(declaration: DistributionSource, scratch_root: Path) -> ProfileSnapshot:
    raw, owned = _read_manifest(declaration)
    manifest_bytes = _canonical_manifest(raw, owned)
    _reject_sensitive_bytes(manifest_bytes)
    output = scratch_root / declaration.name
    # Exclusive creation protects unrelated data already in the scratch root.
    output.mkdir(mode=0o700)
    try:
        _write_file(output / "distribution.yaml", manifest_bytes, 0o644)
        entries: list[SnapshotEntry] = []
        casefolded = {
            ".gitignore".casefold(): ".gitignore",
            "distribution.yaml".casefold(): "distribution.yaml",
        }
        directory_paths: set[PurePosixPath] = set()
        for owned_path in owned:
            source_path = owned_path
            if owned_path == _ENV_TEMPLATE:
                source_path = _INSTALLED_ENV_EXAMPLE
            source = declaration.target.joinpath(*source_path.parts)
            # Declared nested paths can have unowned parent directories.
            _require_directory_chain(source.parent)
            entry_count = len(entries)
            is_directory = _copy_path(source, output, owned_path, entries, casefolded)
            if is_directory:
                if len(entries) == entry_count:
                    raise ProfileSnapshotError(declaration.name, "empty_owned_directory")
                directory_paths.add(owned_path)
        entries.sort(key=lambda entry: entry.path.as_posix())
        gitignore_bytes = _render_gitignore(owned, frozenset(directory_paths))
        _write_file(output / ".gitignore", gitignore_bytes, 0o644)
        return ProfileSnapshot(
            declaration, output, manifest_bytes, gitignore_bytes, tuple(entries)
        )
    except Exception:
        try:
            shutil.rmtree(output)
        except OSError:
            raise ProfileSnapshotError(declaration.name, "cleanup_failed") from None
        raise


def _read_manifest(
    declaration: DistributionSource,
) -> tuple[dict[str, object], tuple[PurePosixPath, ...]]:
    content = _read_regular(declaration.target / "distribution.yaml")
    raw = yaml.load(content.decode("utf-8"), Loader=distributions._UniqueKeyLoader)
    if not isinstance(raw, dict) or any(not isinstance(key, str) for key in raw):
        raise ValueError("manifest shape")
    unknown = frozenset(raw) - frozenset(_DECLARATIVE_KEYS) - _RUNTIME_KEYS
    if unknown or not {"name", "version", "hermes_requires", "distribution_owned"} <= frozenset(raw):
        raise ValueError("manifest keys")
    owned = _snapshot_manifest_owned(raw, declaration.name)
    for key in ("description", "author", "license"):
        if key in raw and not isinstance(raw[key], str):
            raise ValueError("manifest value")
    # Hermes's pure schema API validates requirements without reading any path.
    parsed = distributions.profile_distribution.DistributionManifest.from_dict(raw)
    distributions.profile_distribution.check_hermes_requires(
        parsed.hermes_requires, distributions.HERMES_VERSION
    )
    return raw, owned


def _copy_path(
    source: Path,
    output: Path,
    relative: PurePosixPath,
    entries: list[SnapshotEntry],
    casefolded: dict[str, str],
) -> bool:
    _validate_path(relative)
    _check_casefold(relative, casefolded)
    status = source.lstat()
    _require_safe_source(status)
    destination = output.joinpath(*relative.parts)
    if stat.S_ISDIR(status.st_mode):
        if relative == _ENV_TEMPLATE:
            raise ValueError("unsafe env template source")
        destination.mkdir(parents=True, exist_ok=True, mode=0o700)
        for child in sorted(source.iterdir(), key=lambda path: path.name):
            _copy_path(child, output, relative / child.name, entries, casefolded)
        return True
    destination.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    content = source.read_bytes()
    _reject_sensitive_bytes(content)
    if relative == PurePosixPath("config.yaml"):
        content = _public_profile_config(content)
    mode = _git_mode(status.st_mode)
    _write_file(destination, content, mode)
    entries.append(SnapshotEntry(relative, mode))
    return False


def _read_regular(path: Path) -> bytes:
    status = path.lstat()
    _require_safe_source(status)
    if not stat.S_ISREG(status.st_mode):
        raise ValueError("not a regular file")
    return path.read_bytes()


def _write_file(path: Path, content: bytes, mode: ProfileMode) -> None:
    with path.open("xb") as writer:
        writer.write(content)
    path.chmod(mode)


def _require_directory_chain(path: Path, *, allow_missing: bool = False) -> bool:
    """Check each ancestor before traversing it, so no symlink leaves the tree."""

    if not path.is_absolute() or ".." in path.parts:
        raise ValueError("nonabsolute directory")
    for directory in (*reversed(path.parents), path):
        try:
            status = directory.lstat()
        except FileNotFoundError:
            if allow_missing:
                return False
            raise
        if not stat.S_ISDIR(status.st_mode):
            raise ValueError("unsafe directory")
    return True


def _require_safe_source(source: os.stat_result) -> None:
    if not stat.S_ISREG(source.st_mode) and not stat.S_ISDIR(source.st_mode):
        raise ValueError("unsafe source")
    if stat.S_ISREG(source.st_mode):
        if source.st_nlink != 1:
            raise ValueError("hardlinked source")
        if not source.st_mode & 0o444:
            raise ValueError("unreadable source")


def _require_private_scratch(path: Path) -> None:
    _require_directory_chain(path)
    status = path.lstat()
    if status.st_uid != os.geteuid() or stat.S_IMODE(status.st_mode) & 0o077:
        raise ValueError("scratch unavailable")


def _snapshot_manifest_owned(raw: object, expected_name: str) -> tuple[PurePosixPath, ...]:
    """Validate repository raw fields before Hermes's permissive coercions."""

    if not isinstance(raw, dict) or any(not isinstance(key, str) for key in raw):
        raise ValueError("profile manifest must be a mapping")
    for key in ("name", "version", "hermes_requires"):
        value = raw.get(key)
        if not isinstance(value, str) or not value or value != value.strip():
            raise ValueError("profile manifest identity invalid")
    if raw["name"] != expected_name:
        raise ValueError("profile manifest identity mismatch")
    return _normalize_owned(raw.get("distribution_owned"))


def _normalize_owned(values: object) -> tuple[PurePosixPath, ...]:
    if not isinstance(values, list) or not values:
        raise ValueError("empty ownership")
    normalized = distributions._normalize_owned_paths(values, None, require_sources=False, profile=True)
    for path in normalized:
        if path in {PurePosixPath(".gitignore"), PurePosixPath("distribution.yaml")}:
            raise ValueError("control ownership")
        _validate_path(path)
    return normalized


def _validate_profile_name(name: str) -> None:
    if not isinstance(name, str) or _PROFILE_NAME.fullmatch(name) is None:
        raise ValueError("invalid profile name")


def _validate_path(path: PurePosixPath) -> None:
    distributions._reject_unsupported_cron_path(path)
    for index, component in enumerate(path.parts):
        lowered = component.casefold()
        if not _PORTABLE_COMPONENT.fullmatch(component) or component.endswith((".", " ")):
            raise ValueError("nonportable path")
        if (
            (lowered.startswith(".env") and path != _ENV_TEMPLATE)
            or lowered in _RESERVED_COMPONENTS
            or lowered in _GIT_CONTROL_COMPONENTS
        ):
            raise ValueError("reserved path")
        stem = component.lstrip(".").split(".", 1)[0].casefold()
        if stem in _CREDENTIAL_STEMS:
            raise ValueError("credential filename")
        if (
            index
            and path.parts[index - 1].casefold() == "cron"
            and lowered in {"output", "state"}
        ):
            raise ValueError("reserved path")


def _canonical_manifest(raw: dict[str, object], owned: tuple[PurePosixPath, ...]) -> bytes:
    canonical: dict[str, object] = {}
    for key in _DECLARATIVE_KEYS:
        if key == "distribution_owned":
            canonical[key] = [path.as_posix() for path in owned]
        elif key in raw:
            canonical[key] = raw[key]
    return yaml.safe_dump(canonical, sort_keys=False, allow_unicode=False).encode("ascii")


def _public_profile_config(content: bytes) -> bytes:
    try:
        config = yaml.safe_load(content)
    except yaml.YAMLError:
        return content
    if not isinstance(config, dict):
        return content
    secrets = config.get("secrets")
    if not isinstance(secrets, dict) or "onepassword" not in secrets:
        return content
    return yaml.safe_dump(
        distributions._without_bootstrap_onepassword(config), sort_keys=False
    ).encode("utf-8")


def _check_casefold(path: PurePosixPath, seen: dict[str, str]) -> None:
    for depth in range(1, len(path.parts) + 1):
        logical = PurePosixPath(*path.parts[:depth]).as_posix()
        folded = logical.casefold()
        existing = seen.get(folded)
        if existing is not None and existing != logical:
            raise ValueError("case collision")
        seen[folded] = logical


def _git_mode(mode: int) -> ProfileMode:
    return 0o755 if mode & 0o111 else 0o644


def _render_gitignore(owned: tuple[PurePosixPath, ...], directory_paths: frozenset[PurePosixPath]) -> bytes:
    rules = ["/*", "!/.gitignore", "!/distribution.yaml"]
    seen = set(rules)

    def add(rule: str) -> None:
        if rule not in seen:
            seen.add(rule)
            rules.append(rule)

    for path in owned:
        for depth in range(1, len(path.parts)):
            add(f"!/{'/'.join(path.parts[:depth])}/")
        logical = path.as_posix()
        if path in directory_paths:
            add(f"!/{logical}/")
            add(f"!/{logical}/**")
        else:
            add(f"!/{logical}")
    return ("\n".join(rules) + "\n").encode("ascii")


def _reject_sensitive_bytes(content: bytes) -> None:
    if (
        any(header in content for header in _PRIVATE_KEY_HEADERS)
        or b"-----BEGIN CERTIFICATE-----" in content
        or any(pattern.search(content) for pattern in _SECRET_PATTERNS)
    ):
        raise ValueError("secret candidate")


def _category(error: Exception) -> str:
    return "invalid_manifest" if isinstance(error, UnicodeError) else "invalid_local_profile"
