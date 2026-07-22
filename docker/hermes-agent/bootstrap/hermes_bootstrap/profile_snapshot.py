"""Build immutable, allowlisted local profile projections for publication."""

from __future__ import annotations

import hashlib
import os
import re
import shutil
import stat
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Literal

import yaml
from hermes_cli import __version__ as HERMES_VERSION
from hermes_cli import profile_distribution

from . import distributions
from .errors import RepositoryError
from .filesystem import open_absolute_directory, verify_absolute_directory
from .models import BootstrapManifest, DistributionSource


ProfileMode = Literal[0o644, 0o755]

_DECLARATIVE_KEYS = (
    "name", "version", "description", "hermes_requires", "author",
    "license", "env_requires", "distribution_owned",
)
_RUNTIME_KEYS = frozenset({"source", "installed_at"})
_READ_CHUNK_BYTES = 64 * 1024
_SECRET_OVERLAP_BYTES = 256
_PROFILE_NAME = re.compile(r"[a-z][a-z0-9-]*\Z")
_PORTABLE_COMPONENT = re.compile(r"[A-Za-z0-9._-]+\Z")
_GITHUB_TOKEN = re.compile(rb"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})\b")
_SLACK_TOKEN = re.compile(rb"\bxox(?:b|p|a|r|s)-[A-Za-z0-9-]{8,}\b")
_PRIVATE_KEY = re.compile(rb"-----BEGIN (?:[A-Z0-9 ]+ )?PRIVATE KEY-----")
_RESERVED_COMPONENTS = frozenset(
    {
        ".bootstrap", ".git", "auth", "auth.json", "browser", "browser_data",
        "cache", "caches", "credential", "credentials", "home", "locks", "logs",
        "memories", "oauth", "plans", "sessions", "token", "tokens", "workspace",
    }
)
_CREDENTIAL_STEMS = frozenset({"auth", "credential", "credentials", "secret", "token", "tokens"})


@dataclass(frozen=True)
class SnapshotEntry:
    path: PurePosixPath
    mode: ProfileMode
    size: int
    sha256: str


@dataclass(frozen=True)
class ProfileSnapshot:
    declaration: DistributionSource
    root: Path
    manifest_bytes: bytes
    gitignore_bytes: bytes
    entries: tuple[SnapshotEntry, ...]
    digest: str


@dataclass(frozen=True)
class PreparedProfiles:
    snapshots: tuple[ProfileSnapshot, ...]
    missing: tuple[DistributionSource, ...]


@dataclass(frozen=True)
class ProfileSnapshotError(RepositoryError):
    """A redacted, immutable local-profile preflight failure."""

    profile: str
    category: str

    def __post_init__(self) -> None:
        RepositoryError.__init__(self, f"profile snapshot rejected ({self.category})")


def prepare_profile_snapshots(
    manifest: BootstrapManifest, scratch_root: Path, *, allow_missing: bool
) -> PreparedProfiles:
    """Copy every valid installed profile to caller-owned private scratch space."""

    _require_private_scratch(scratch_root)
    scratch_fd = open_absolute_directory(scratch_root)
    try:
        _require_private_scratch_status(os.fstat(scratch_fd))
    except Exception:
        os.close(scratch_fd)
        raise ValueError("scratch unavailable") from None
    snapshots: list[ProfileSnapshot] = []
    missing: list[DistributionSource] = []
    created: list[str] = []
    try:
        for declaration in manifest.profiles:
            try:
                _validate_profile_name(declaration.name)
            except Exception:
                raise ProfileSnapshotError(declaration.name, "invalid_profile_name") from None
            if declaration.target != manifest.data_root / "profiles" / declaration.name:
                raise ProfileSnapshotError(declaration.name, "invalid_profile_target")
            if not _path_exists(declaration.target):
                if allow_missing:
                    missing.append(declaration)
                    continue
                raise ProfileSnapshotError(declaration.name, "missing_profile")
            try:
                snapshot = _prepare_one(declaration, scratch_root, scratch_fd)
            except ProfileSnapshotError:
                raise
            except Exception as error:
                raise ProfileSnapshotError(declaration.name, _category(error)) from None
            snapshots.append(snapshot)
            created.append(declaration.name)
    except ProfileSnapshotError:
        for name in reversed(created):
            _remove_snapshot(scratch_fd, name)
        raise
    finally:
        os.close(scratch_fd)
    return PreparedProfiles(tuple(snapshots), tuple(missing))


def _prepare_one(declaration: DistributionSource, scratch_root: Path, scratch_fd: int) -> ProfileSnapshot:
    output = scratch_root / declaration.name
    try:
        os.stat(declaration.name, dir_fd=scratch_fd, follow_symlinks=False)
    except FileNotFoundError:
        pass
    else:
        raise ValueError("snapshot output already exists")
    source_fd = open_absolute_directory(declaration.target)
    output_fd: int | None = None
    output_created = False
    try:
        raw, manifest_stat = _read_manifest_compatibly(declaration, source_fd)
        owned = _normalize_owned(raw["distribution_owned"])
        manifest_bytes = _canonical_manifest(raw, owned)
        _reject_sensitive_bytes(manifest_bytes)
        os.mkdir(declaration.name, mode=0o700, dir_fd=scratch_fd)
        output_created = True
        output_fd = _open_output_directory(scratch_fd, declaration.name)
        _write_private_file_at(output_fd, "distribution.yaml", manifest_bytes, 0o644)
        entries: list[SnapshotEntry] = []
        casefolded: set[str] = set()
        directory_paths: set[PurePosixPath] = set()
        for owned_path in owned:
            is_directory = _copy_declared_path(source_fd, owned_path, output_fd, entries, casefolded)
            if is_directory:
                directory_paths.add(owned_path)
        _validate_canonical_manifest(output_fd, declaration, owned, manifest_bytes)
        _verify_manifest_current(source_fd, manifest_stat)
        verify_absolute_directory(declaration.target, source_fd)
        entries.sort(key=lambda entry: entry.path.as_posix())
        gitignore_bytes = _render_gitignore(owned, frozenset(directory_paths))
        _write_private_file_at(output_fd, ".gitignore", gitignore_bytes, 0o644)
        verify_absolute_directory(output, output_fd)
        verify_absolute_directory(scratch_root, scratch_fd)
        digest = _snapshot_digest(manifest_bytes, gitignore_bytes, entries)
        return ProfileSnapshot(declaration, output, manifest_bytes, gitignore_bytes, tuple(entries), digest)
    except Exception:
        if output_created:
            _remove_snapshot(scratch_fd, declaration.name)
        raise
    finally:
        os.close(source_fd)
        if output_fd is not None:
            os.close(output_fd)


def _read_manifest_compatibly(declaration: DistributionSource, source_fd: int) -> tuple[dict[str, object], os.stat_result]:
    """Read exact manifest bytes before validating them in private scratch."""

    content, manifest_stat = _read_regular(source_fd, "distribution.yaml")
    raw = yaml.load(content.decode("utf-8"), Loader=distributions._UniqueKeyLoader)
    if not isinstance(raw, dict) or any(not isinstance(key, str) for key in raw):
        raise ValueError("manifest shape")
    unknown = frozenset(raw) - frozenset(_DECLARATIVE_KEYS) - _RUNTIME_KEYS
    if unknown or not {"name", "version", "hermes_requires", "distribution_owned"} <= frozenset(raw):
        raise ValueError("manifest keys")
    if raw["name"] != declaration.name or not isinstance(raw["distribution_owned"], list):
        raise ValueError("manifest identity")
    if any(not isinstance(value, str) for value in raw["distribution_owned"]):
        raise ValueError("manifest ownership")
    for key in ("description", "author", "license"):
        if key in raw and not isinstance(raw[key], str):
            raise ValueError("manifest value")
    return raw, manifest_stat


def _validate_canonical_manifest(
    root_fd: int,
    declaration: DistributionSource,
    owned: tuple[PurePosixPath, ...],
    expected_bytes: bytes,
) -> None:
    """Use Hermes on the exact bytes and copied sources that will be published."""

    current_bytes, _ = _read_regular(root_fd, "distribution.yaml")
    if current_bytes != expected_bytes:
        raise ValueError("manifest changed")
    raw = yaml.load(current_bytes.decode("utf-8"), Loader=distributions._UniqueKeyLoader)
    parsed = profile_distribution.DistributionManifest.from_dict(raw)
    if parsed.name != declaration.name or parsed.hermes_requires != raw["hermes_requires"]:
        raise ValueError("manifest identity")
    profile_distribution.check_hermes_requires(parsed.hermes_requires, HERMES_VERSION)
    parsed_owned = distributions._normalize_owned_paths(raw["distribution_owned"], None, require_sources=False, profile=True)
    if parsed_owned != owned or _read_regular(root_fd, "distribution.yaml")[0] != expected_bytes:
        raise ValueError("manifest ownership")


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
    for index, component in enumerate(path.parts):
        lowered = component.casefold()
        if not _PORTABLE_COMPONENT.fullmatch(component) or component.endswith((".", " ")):
            raise ValueError("nonportable path")
        if lowered.startswith(".env") or lowered in _RESERVED_COMPONENTS:
            raise ValueError("reserved path")
        if index and path.parts[0].casefold() == "cron" and lowered in {"output", "state"}:
            raise ValueError("reserved path")
    stem = path.name.rsplit(".", 1)[0].casefold()
    if stem in _CREDENTIAL_STEMS:
        raise ValueError("credential filename")


def _canonical_manifest(raw: dict[str, object], owned: tuple[PurePosixPath, ...]) -> bytes:
    canonical: dict[str, object] = {}
    for key in _DECLARATIVE_KEYS:
        if key == "distribution_owned":
            canonical[key] = [path.as_posix() for path in owned]
        elif key in raw:
            canonical[key] = raw[key]
    return yaml.safe_dump(canonical, sort_keys=False, allow_unicode=False).encode("ascii")


def _copy_declared_path(
    source_fd: int,
    path: PurePosixPath,
    output_fd: int,
    entries: list[SnapshotEntry],
    casefolded: set[str],
) -> bool:
    source_fds = [os.dup(source_fd)]
    output_fds = [os.dup(output_fd)]
    ancestors: list[tuple[int, str, int, tuple[os.stat_result, os.stat_result]]] = []
    try:
        for component in path.parts[:-1]:
            source_child_fd, source_identity = _open_source_directory(source_fds[-1], component)
            output_child_fd = _create_output_directory(output_fds[-1], component)
            ancestors.append((source_fds[-1], component, source_child_fd, source_identity))
            source_fds.append(source_child_fd)
            output_fds.append(output_child_fd)
        source_parent_fd = source_fds[-1]
        output_parent_fd = output_fds[-1]
        source = os.stat(path.name, dir_fd=source_parent_fd, follow_symlinks=False)
        _require_safe_source(source)
        _check_casefold(path, casefolded)
        if stat.S_ISDIR(source.st_mode):
            source_child_fd, source_identity = _open_source_directory(source_parent_fd, path.name)
            output_child_fd = _create_output_directory(output_parent_fd, path.name)
            try:
                _copy_directory(
                    source_child_fd, source_parent_fd, path.name, source_identity, path, output_child_fd, entries, casefolded
                )
            finally:
                os.close(source_child_fd)
                os.close(output_child_fd)
            result = True
        else:
            _copy_regular(source_parent_fd, path.name, path, output_parent_fd, entries)
            result = False
        for parent_fd, name, descriptor, identity in reversed(ancestors):
            _verify_source_directory(parent_fd, name, descriptor, identity)
        return result
    finally:
        for descriptor in reversed(source_fds):
            os.close(descriptor)
        for descriptor in reversed(output_fds):
            os.close(descriptor)


def _copy_directory(
    source_fd: int,
    source_parent_fd: int,
    source_name: str,
    source_identity: tuple[os.stat_result, os.stat_result],
    prefix: PurePosixPath,
    output_fd: int,
    entries: list[SnapshotEntry],
    casefolded: set[str],
) -> None:
    with os.scandir(source_fd) as iterator:
        names = sorted(entry.name for entry in iterator)
    for name in names:
        relative = prefix / name
        _validate_path(relative)
        _check_casefold(relative, casefolded)
        source = os.stat(name, dir_fd=source_fd, follow_symlinks=False)
        _require_safe_source(source)
        if stat.S_ISDIR(source.st_mode):
            source_child_fd, child_identity = _open_source_directory(source_fd, name)
            output_child_fd = _create_output_directory(output_fd, name)
            try:
                _copy_directory(
                    source_child_fd, source_fd, name, child_identity, relative, output_child_fd, entries, casefolded
                )
            finally:
                os.close(source_child_fd)
                os.close(output_child_fd)
        else:
            _copy_regular(source_fd, name, relative, output_fd, entries)
    _verify_source_directory(source_parent_fd, source_name, source_fd, source_identity)


def _copy_regular(parent_fd: int, name: str, relative: PurePosixPath, output_fd: int, entries: list[SnapshotEntry]) -> None:
    source_fd = _open_regular(parent_fd, name)
    destination_fd: int | None = None
    try:
        before = os.fstat(source_fd)
        destination_fd = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC, 0o600, dir_fd=output_fd)
        digest = hashlib.sha256()
        size = 0
        overlap = b""
        while chunk := os.read(source_fd, _READ_CHUNK_BYTES):
            _reject_sensitive_bytes(overlap + chunk)
            _write_descriptor(destination_fd, chunk)
            digest.update(chunk)
            size += len(chunk)
            overlap = (overlap + chunk)[-_SECRET_OVERLAP_BYTES:]
        _verify_regular(parent_fd, name, source_fd, before, size)
        os.fsync(destination_fd)
    finally:
        os.close(source_fd)
        if destination_fd is not None:
            os.close(destination_fd)
    mode = _git_mode(before.st_mode)
    os.chmod(name, mode, dir_fd=output_fd, follow_symlinks=False)
    entries.append(SnapshotEntry(relative, mode, size, digest.hexdigest()))


def _read_regular(parent_fd: int, name: str) -> tuple[bytes, os.stat_result]:
    descriptor = _open_regular(parent_fd, name)
    try:
        before = os.fstat(descriptor)
        chunks: list[bytes] = []
        while chunk := os.read(descriptor, _READ_CHUNK_BYTES):
            chunks.append(chunk)
        content = b"".join(chunks)
        _verify_regular(parent_fd, name, descriptor, before, len(content))
        return content, before
    finally:
        os.close(descriptor)


def _open_regular(parent_fd: int, name: str) -> int:
    flags = os.O_RDONLY | os.O_CLOEXEC | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(name, flags, dir_fd=parent_fd)
    try:
        source = os.fstat(descriptor)
        _require_safe_source(source)
        if not source.st_mode & 0o444:
            raise ValueError("unreadable source")
        return descriptor
    except Exception:
        os.close(descriptor)
        raise


def _verify_regular(parent_fd: int, name: str, descriptor: int, before: os.stat_result, size: int) -> None:
    after = os.fstat(descriptor)
    if (
        size != before.st_size
        or (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns)
        != (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns)
    ):
        raise ValueError("source changed")
    current = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
    if (before.st_dev, before.st_ino) != (current.st_dev, current.st_ino):
        raise ValueError("source replaced")


def _verify_manifest_current(source_fd: int, before: os.stat_result) -> None:
    current = os.stat("distribution.yaml", dir_fd=source_fd, follow_symlinks=False)
    _require_safe_source(current)
    if (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns) != (
        current.st_dev,
        current.st_ino,
        current.st_size,
        current.st_mtime_ns,
    ):
        raise ValueError("manifest changed")


def _open_source_directory(parent_fd: int, name: str) -> tuple[int, tuple[os.stat_result, os.stat_result]]:
    expected = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
    flags = os.O_RDONLY | os.O_CLOEXEC | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(name, flags, dir_fd=parent_fd)
    try:
        actual = os.fstat(descriptor)
        if (
            stat.S_ISLNK(expected.st_mode)
            or not stat.S_ISDIR(actual.st_mode)
            or (expected.st_dev, expected.st_ino) != (actual.st_dev, actual.st_ino)
        ):
            raise ValueError("unsafe directory")
        return descriptor, (expected, actual)
    except Exception:
        os.close(descriptor)
        raise


def _verify_source_directory(
    parent_fd: int,
    name: str,
    descriptor: int,
    before: tuple[os.stat_result, os.stat_result],
) -> None:
    current = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
    actual = os.fstat(descriptor)
    expected, opened = before
    if any(
        _directory_identity(item) != _directory_identity(expected)
        for item in (opened, current, actual)
    ):
        raise ValueError("source directory changed")


def _directory_identity(status: os.stat_result) -> tuple[int, int, int, int]:
    return status.st_dev, status.st_ino, status.st_mode, status.st_mtime_ns


def _create_output_directory(parent_fd: int, name: str) -> int:
    try:
        os.mkdir(name, mode=0o700, dir_fd=parent_fd)
    except FileExistsError:
        pass
    return _open_output_directory(parent_fd, name)


def _open_output_directory(parent_fd: int, name: str) -> int:
    flags = os.O_RDONLY | os.O_CLOEXEC | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(name, flags, dir_fd=parent_fd)
    try:
        expected = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
        actual = os.fstat(descriptor)
        if (
            stat.S_ISLNK(expected.st_mode)
            or not stat.S_ISDIR(actual.st_mode)
            or (expected.st_dev, expected.st_ino) != (actual.st_dev, actual.st_ino)
        ):
            raise ValueError("unsafe output directory")
        return descriptor
    except Exception:
        os.close(descriptor)
        raise


def _require_safe_source(source: os.stat_result) -> None:
    if not stat.S_ISREG(source.st_mode) and not stat.S_ISDIR(source.st_mode):
        raise ValueError("unsafe source")
    if stat.S_ISREG(source.st_mode) and source.st_nlink != 1:
        raise ValueError("hardlinked source")


def _check_casefold(path: PurePosixPath, seen: set[str]) -> None:
    folded = path.as_posix().casefold()
    if folded in seen:
        raise ValueError("case collision")
    seen.add(folded)


def _git_mode(mode: int) -> ProfileMode:
    return 0o755 if mode & 0o111 else 0o644


def _write_private_file_at(parent_fd: int, name: str, content: bytes, mode: ProfileMode) -> None:
    descriptor = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC, 0o600, dir_fd=parent_fd)
    try:
        _write_descriptor(descriptor, content)
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
    os.chmod(name, mode, dir_fd=parent_fd, follow_symlinks=False)


def _write_descriptor(descriptor: int, content: bytes) -> None:
    view = memoryview(content)
    while view:
        written = os.write(descriptor, view)
        view = view[written:]


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


def _snapshot_digest(manifest_bytes: bytes, gitignore_bytes: bytes, entries: list[SnapshotEntry]) -> str:
    controls = (
        SnapshotEntry(PurePosixPath(".gitignore"), 0o644, len(gitignore_bytes), hashlib.sha256(gitignore_bytes).hexdigest()),
        SnapshotEntry(PurePosixPath("distribution.yaml"), 0o644, len(manifest_bytes), hashlib.sha256(manifest_bytes).hexdigest()),
    )
    payload = b"".join(
        f"{entry.path.as_posix()}\0{entry.mode:o}\0{entry.sha256}\n".encode("ascii")
        for entry in sorted((*controls, *entries), key=lambda item: item.path.as_posix())
    )
    return hashlib.sha256(payload).hexdigest()


def _reject_sensitive_bytes(content: bytes) -> None:
    if _GITHUB_TOKEN.search(content) or _SLACK_TOKEN.search(content) or _PRIVATE_KEY.search(content):
        raise ValueError("secret candidate")


def _require_private_scratch(path: Path) -> None:
    try:
        status = path.lstat()
    except OSError as error:
        raise ValueError("scratch unavailable") from error
    _require_private_scratch_status(status)


def _require_private_scratch_status(status: os.stat_result) -> None:
    if (
        stat.S_ISLNK(status.st_mode)
        or not stat.S_ISDIR(status.st_mode)
        or status.st_uid != os.geteuid()
        or stat.S_IMODE(status.st_mode) & 0o077
    ):
        raise ValueError("scratch unavailable")


def _path_exists(path: Path) -> bool:
    try:
        path.lstat()
    except FileNotFoundError:
        return False
    return True


def _remove_snapshot(scratch_fd: int, name: str) -> None:
    try:
        shutil.rmtree(name, dir_fd=scratch_fd)
    except OSError:
        pass


def _category(error: Exception) -> str:
    if isinstance(error, UnicodeError):
        return "invalid_manifest"
    return "invalid_local_profile"
