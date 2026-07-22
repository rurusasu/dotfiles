"""Build immutable, allowlisted local profile projections for publication."""

from __future__ import annotations

import hashlib
import os
import re
import stat
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Literal

import yaml

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
_SLACK_TOKEN = re.compile(
    rb"\b(?:xox(?:b|p|a|r|s)-[A-Za-z0-9-]{8,}|xapp-[A-Za-z0-9-]+)\b"
)
_PRIVATE_KEY = re.compile(rb"-----BEGIN (?:[A-Z0-9 ]+ )?PRIVATE KEY-----")
_GIT_CONTROL_COMPONENTS = frozenset({".git", ".gitignore", ".gitattributes", ".gitmodules"})
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


@dataclass(frozen=True)
class _ExpectedFile:
    path: PurePosixPath
    mode: ProfileMode
    size: int
    sha256: str
    device: int
    inode: int


@dataclass(frozen=True)
class _ExpectedDirectory:
    path: PurePosixPath
    mode: int
    device: int
    inode: int


@dataclass(frozen=True)
class _PreparedSnapshot:
    snapshot: ProfileSnapshot
    output_fd: int
    output_identity: tuple[int, int]
    files: tuple[_ExpectedFile, ...]
    directories: tuple[_ExpectedDirectory, ...]


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
    prepared: list[_PreparedSnapshot] = []
    missing: list[DistributionSource] = []
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
                item = _prepare_one(declaration, scratch_root, scratch_fd)
            except ProfileSnapshotError:
                raise
            except Exception as error:
                raise ProfileSnapshotError(declaration.name, _category(error)) from None
            prepared.append(item)
        for item in prepared:
            try:
                _verify_prepared_snapshot(scratch_root, scratch_fd, item)
            except Exception as error:
                raise ProfileSnapshotError(item.snapshot.declaration.name, _category(error)) from None
    except ProfileSnapshotError:
        cleanup_profile: str | None = None
        for item in reversed(prepared):
            try:
                _remove_snapshot(scratch_fd, item.output_fd, item.output_identity)
            except Exception:
                if cleanup_profile is None:
                    cleanup_profile = item.snapshot.declaration.name
        if cleanup_profile is not None:
            raise ProfileSnapshotError(cleanup_profile, "cleanup_failed") from None
        raise
    finally:
        for item in prepared:
            os.close(item.output_fd)
        os.close(scratch_fd)
    return PreparedProfiles(tuple(item.snapshot for item in prepared), tuple(missing))


def _prepare_one(declaration: DistributionSource, scratch_root: Path, scratch_fd: int) -> _PreparedSnapshot:
    output = scratch_root / declaration.name
    try:
        os.stat(declaration.name, dir_fd=scratch_fd, follow_symlinks=False)
    except FileNotFoundError:
        pass
    else:
        raise ValueError("snapshot output already exists")
    source_fd = open_absolute_directory(declaration.target)
    output_fd: int | None = None
    output_identity: tuple[int, int] | None = None
    output_created = False
    keep_output_open = False
    try:
        raw, manifest_stat = _read_manifest_compatibly(declaration, source_fd)
        owned = _normalize_owned(raw["distribution_owned"])
        manifest_bytes = _canonical_manifest(raw, owned)
        _reject_sensitive_bytes(manifest_bytes)
        os.mkdir(declaration.name, mode=0o700, dir_fd=scratch_fd)
        output_created = True
        created_status = os.stat(declaration.name, dir_fd=scratch_fd, follow_symlinks=False)
        if not stat.S_ISDIR(created_status.st_mode):
            raise ValueError("unsafe output directory")
        output_identity = (created_status.st_dev, created_status.st_ino)
        output_fd = _open_output_directory(scratch_fd, declaration.name)
        os.fchmod(output_fd, 0o700)
        os.fsync(output_fd)
        output_status = os.fstat(output_fd)
        if output_identity != (output_status.st_dev, output_status.st_ino):
            raise ValueError("unsafe output directory")
        expected_files = [
            _write_private_file_at(output_fd, "distribution.yaml", manifest_bytes, 0o644)
        ]
        entries: list[SnapshotEntry] = []
        casefolded = {
            ".gitignore".casefold(): ".gitignore",
            "distribution.yaml".casefold(): "distribution.yaml",
        }
        expected_directories: dict[PurePosixPath, _ExpectedDirectory] = {}
        directory_paths: set[PurePosixPath] = set()
        for owned_path in owned:
            is_directory = _copy_declared_path(
                source_fd,
                owned_path,
                output_fd,
                entries,
                expected_files,
                expected_directories,
                casefolded,
            )
            if is_directory:
                directory_paths.add(owned_path)
        _validate_canonical_manifest(output_fd, declaration, owned, manifest_bytes)
        _verify_manifest_current(source_fd, manifest_stat)
        verify_absolute_directory(declaration.target, source_fd)
        entries.sort(key=lambda entry: entry.path.as_posix())
        gitignore_bytes = _render_gitignore(owned, frozenset(directory_paths))
        expected_files.append(_write_private_file_at(output_fd, ".gitignore", gitignore_bytes, 0o644))
        digest = _snapshot_digest(manifest_bytes, gitignore_bytes, entries)
        snapshot = ProfileSnapshot(declaration, output, manifest_bytes, gitignore_bytes, tuple(entries), digest)
        result = _PreparedSnapshot(
            snapshot,
            output_fd,
            output_identity,
            tuple(expected_files),
            tuple(expected_directories.values()),
        )
        _verify_prepared_snapshot(scratch_root, scratch_fd, result)
        keep_output_open = True
        return result
    except Exception:
        if output_created:
            if output_identity is None:
                raise ProfileSnapshotError(declaration.name, "cleanup_failed") from None
            try:
                _remove_snapshot(scratch_fd, output_fd, output_identity)
            except Exception:
                raise ProfileSnapshotError(declaration.name, "cleanup_failed") from None
        raise
    finally:
        os.close(source_fd)
        if output_fd is not None and not keep_output_open:
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
    projection = _descriptor_projection(root_fd)
    _manifest, parsed_owned = distributions._read_profile_manifest_at(
        projection,
        declaration.name,
        require_sources=True,
    )
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
        if (
            lowered.startswith(".env")
            or lowered in _RESERVED_COMPONENTS
            or lowered in _GIT_CONTROL_COMPONENTS
        ):
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
    expected_files: list[_ExpectedFile],
    expected_directories: dict[PurePosixPath, _ExpectedDirectory],
    casefolded: dict[str, str],
) -> bool:
    source_fds = [os.dup(source_fd)]
    output_fds = [os.dup(output_fd)]
    ancestors: list[tuple[int, str, int, tuple[os.stat_result, os.stat_result]]] = []
    try:
        prefix = PurePosixPath()
        for component in path.parts[:-1]:
            prefix /= component
            source_child_fd, source_identity = _open_source_directory(source_fds[-1], component)
            output_child_fd = _create_output_directory(
                output_fds[-1],
                component,
                prefix,
                expected_directories,
            )
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
            output_child_fd = _create_output_directory(
                output_parent_fd,
                path.name,
                path,
                expected_directories,
            )
            try:
                _copy_directory(
                    source_child_fd,
                    source_parent_fd,
                    path.name,
                    source_identity,
                    path,
                    output_child_fd,
                    entries,
                    expected_files,
                    expected_directories,
                    casefolded,
                )
            finally:
                os.close(source_child_fd)
                os.close(output_child_fd)
            result = True
        else:
            _copy_regular(
                source_parent_fd,
                path.name,
                path,
                output_parent_fd,
                entries,
                expected_files,
            )
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
    expected_files: list[_ExpectedFile],
    expected_directories: dict[PurePosixPath, _ExpectedDirectory],
    casefolded: dict[str, str],
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
            output_child_fd = _create_output_directory(
                output_fd,
                name,
                relative,
                expected_directories,
            )
            try:
                _copy_directory(
                    source_child_fd,
                    source_fd,
                    name,
                    child_identity,
                    relative,
                    output_child_fd,
                    entries,
                    expected_files,
                    expected_directories,
                    casefolded,
                )
            finally:
                os.close(source_child_fd)
                os.close(output_child_fd)
        else:
            _copy_regular(source_fd, name, relative, output_fd, entries, expected_files)
    _verify_source_directory(source_parent_fd, source_name, source_fd, source_identity)


def _copy_regular(
    parent_fd: int,
    name: str,
    relative: PurePosixPath,
    output_fd: int,
    entries: list[SnapshotEntry],
    expected_files: list[_ExpectedFile],
) -> None:
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
        mode = _git_mode(before.st_mode)
        os.fchmod(destination_fd, mode)
        os.fsync(destination_fd)
        destination = _verify_destination_descriptor(
            output_fd,
            name,
            destination_fd,
            mode,
            size,
        )
    finally:
        os.close(source_fd)
        if destination_fd is not None:
            os.close(destination_fd)
    sha256 = digest.hexdigest()
    entries.append(SnapshotEntry(relative, mode, size, sha256))
    expected_files.append(
        _ExpectedFile(relative, mode, size, sha256, destination.st_dev, destination.st_ino)
    )


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
    _require_safe_source(after)
    if (
        size != before.st_size
        or _regular_identity(before) != _regular_identity(after)
    ):
        raise ValueError("source changed")
    current = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
    _require_safe_source(current)
    if _regular_identity(before) != _regular_identity(current):
        raise ValueError("source replaced")


def _verify_manifest_current(source_fd: int, before: os.stat_result) -> None:
    current = os.stat("distribution.yaml", dir_fd=source_fd, follow_symlinks=False)
    _require_safe_source(current)
    if _regular_identity(before) != _regular_identity(current):
        raise ValueError("manifest changed")


def _regular_identity(status: os.stat_result) -> tuple[int, int, int, int, int, int]:
    return (
        status.st_dev,
        status.st_ino,
        status.st_mode,
        status.st_nlink,
        status.st_size,
        status.st_mtime_ns,
    )


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


def _create_output_directory(
    parent_fd: int,
    name: str,
    relative: PurePosixPath,
    expected_directories: dict[PurePosixPath, _ExpectedDirectory],
) -> int:
    created = False
    try:
        os.mkdir(name, mode=0o700, dir_fd=parent_fd)
        created = True
    except FileExistsError:
        if relative not in expected_directories:
            raise ValueError("unexpected output directory") from None
    descriptor = _open_output_directory(parent_fd, name)
    try:
        if created:
            os.fchmod(descriptor, 0o700)
            os.fsync(descriptor)
            status = os.fstat(descriptor)
            expected_directories[relative] = _ExpectedDirectory(
                relative,
                stat.S_IMODE(status.st_mode),
                status.st_dev,
                status.st_ino,
            )
        else:
            _verify_expected_directory_descriptor(
                parent_fd,
                name,
                descriptor,
                expected_directories[relative],
            )
        return descriptor
    except Exception:
        os.close(descriptor)
        raise


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


def _write_private_file_at(
    parent_fd: int,
    name: str,
    content: bytes,
    mode: ProfileMode,
) -> _ExpectedFile:
    descriptor = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC, 0o600, dir_fd=parent_fd)
    try:
        _write_descriptor(descriptor, content)
        os.fchmod(descriptor, mode)
        os.fsync(descriptor)
        status = _verify_destination_descriptor(
            parent_fd,
            name,
            descriptor,
            mode,
            len(content),
        )
    finally:
        os.close(descriptor)
    return _ExpectedFile(
        PurePosixPath(name),
        mode,
        len(content),
        hashlib.sha256(content).hexdigest(),
        status.st_dev,
        status.st_ino,
    )


def _verify_destination_descriptor(
    parent_fd: int,
    name: str,
    descriptor: int,
    mode: ProfileMode,
    size: int,
) -> os.stat_result:
    current = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
    actual = os.fstat(descriptor)
    for status in (current, actual):
        if (
            not stat.S_ISREG(status.st_mode)
            or status.st_nlink != 1
            or stat.S_IMODE(status.st_mode) != mode
            or status.st_size != size
        ):
            raise ValueError("snapshot file changed")
    if (current.st_dev, current.st_ino) != (actual.st_dev, actual.st_ino):
        raise ValueError("snapshot file replaced")
    return actual


def _verify_expected_directory_descriptor(
    parent_fd: int,
    name: str,
    descriptor: int,
    expected: _ExpectedDirectory,
) -> None:
    current = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
    actual = os.fstat(descriptor)
    for status in (current, actual):
        if (
            not stat.S_ISDIR(status.st_mode)
            or stat.S_IMODE(status.st_mode) != expected.mode
            or (status.st_dev, status.st_ino) != (expected.device, expected.inode)
        ):
            raise ValueError("snapshot directory changed")


def _descriptor_projection(descriptor: int) -> Path:
    expected = os.fstat(descriptor)
    for parent in (Path("/proc/self/fd"), Path("/dev/fd")):
        candidate = parent / str(descriptor)
        try:
            current = candidate.stat()
        except OSError:
            continue
        if stat.S_ISDIR(current.st_mode) and (current.st_dev, current.st_ino) == (
            expected.st_dev,
            expected.st_ino,
        ):
            return candidate
    raise ValueError("descriptor projection unavailable")


def _verify_prepared_snapshot(
    scratch_root: Path,
    scratch_fd: int,
    prepared: _PreparedSnapshot,
) -> None:
    verify_absolute_directory(scratch_root, scratch_fd)
    _verify_output_root(
        scratch_fd,
        prepared.snapshot.declaration.name,
        prepared.output_fd,
        prepared.output_identity,
    )
    verify_absolute_directory(prepared.snapshot.root, prepared.output_fd)
    os.fsync(prepared.output_fd)
    _verify_snapshot_tree(prepared.output_fd, prepared.files, prepared.directories)
    _verify_output_root(
        scratch_fd,
        prepared.snapshot.declaration.name,
        prepared.output_fd,
        prepared.output_identity,
    )
    verify_absolute_directory(prepared.snapshot.root, prepared.output_fd)
    verify_absolute_directory(scratch_root, scratch_fd)


def _verify_output_root(
    scratch_fd: int,
    name: str,
    output_fd: int,
    expected_identity: tuple[int, int],
) -> None:
    current = os.stat(name, dir_fd=scratch_fd, follow_symlinks=False)
    actual = os.fstat(output_fd)
    for status in (current, actual):
        if (
            not stat.S_ISDIR(status.st_mode)
            or stat.S_IMODE(status.st_mode) != 0o700
            or status.st_uid != os.geteuid()
            or (status.st_dev, status.st_ino) != expected_identity
        ):
            raise ValueError("snapshot root changed")


def _verify_snapshot_tree(
    output_fd: int,
    files: tuple[_ExpectedFile, ...],
    directories: tuple[_ExpectedDirectory, ...],
) -> None:
    expected_files = {item.path: item for item in files}
    expected_directories = {item.path: item for item in directories}
    if len(expected_files) != len(files) or len(expected_directories) != len(directories):
        raise ValueError("duplicate snapshot entry")
    seen_files: set[PurePosixPath] = set()
    seen_directories: set[PurePosixPath] = set()
    _verify_snapshot_directory(
        output_fd,
        PurePosixPath(),
        expected_files,
        expected_directories,
        seen_files,
        seen_directories,
    )
    if seen_files != set(expected_files) or seen_directories != set(expected_directories):
        raise ValueError("snapshot inventory changed")


def _verify_snapshot_directory(
    directory_fd: int,
    prefix: PurePosixPath,
    expected_files: dict[PurePosixPath, _ExpectedFile],
    expected_directories: dict[PurePosixPath, _ExpectedDirectory],
    seen_files: set[PurePosixPath],
    seen_directories: set[PurePosixPath],
) -> None:
    with os.scandir(directory_fd) as iterator:
        names = sorted(entry.name for entry in iterator)
    for name in names:
        relative = prefix / name
        current = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
        if stat.S_ISDIR(current.st_mode):
            expected = expected_directories.get(relative)
            if expected is None:
                raise ValueError("unexpected snapshot directory")
            child_fd = _open_output_directory(directory_fd, name)
            try:
                _verify_expected_directory_descriptor(directory_fd, name, child_fd, expected)
                seen_directories.add(relative)
                _verify_snapshot_directory(
                    child_fd,
                    relative,
                    expected_files,
                    expected_directories,
                    seen_files,
                    seen_directories,
                )
                _verify_expected_directory_descriptor(directory_fd, name, child_fd, expected)
            finally:
                os.close(child_fd)
        elif stat.S_ISREG(current.st_mode):
            expected_file = expected_files.get(relative)
            if expected_file is None:
                raise ValueError("unexpected snapshot file")
            _verify_expected_file(directory_fd, name, expected_file)
            seen_files.add(relative)
        else:
            raise ValueError("unsafe snapshot entry")


def _verify_expected_file(parent_fd: int, name: str, expected: _ExpectedFile) -> None:
    descriptor = os.open(
        name,
        os.O_RDONLY | os.O_CLOEXEC | getattr(os, "O_NOFOLLOW", 0),
        dir_fd=parent_fd,
    )
    try:
        before = os.fstat(descriptor)
        _require_expected_file_status(before, expected)
        current = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
        _require_expected_file_status(current, expected)
        digest = hashlib.sha256()
        size = 0
        while chunk := os.read(descriptor, _READ_CHUNK_BYTES):
            digest.update(chunk)
            size += len(chunk)
        after = os.fstat(descriptor)
        _require_expected_file_status(after, expected)
        current = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
        _require_expected_file_status(current, expected)
        if size != expected.size or digest.hexdigest() != expected.sha256:
            raise ValueError("snapshot content changed")
    finally:
        os.close(descriptor)


def _require_expected_file_status(status: os.stat_result, expected: _ExpectedFile) -> None:
    if (
        not stat.S_ISREG(status.st_mode)
        or status.st_nlink != 1
        or stat.S_IMODE(status.st_mode) != expected.mode
        or status.st_size != expected.size
        or (status.st_dev, status.st_ino) != (expected.device, expected.inode)
    ):
        raise ValueError("snapshot file changed")


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


def _remove_snapshot(
    scratch_fd: int,
    output_fd: int | None,
    expected_identity: tuple[int, int],
) -> None:
    cleanup_fd: int | None = os.dup(output_fd) if output_fd is not None else None
    try:
        if cleanup_fd is None:
            name = _find_snapshot_name(scratch_fd, expected_identity)
            if name is None:
                raise OSError("snapshot cleanup target unavailable")
            cleanup_fd = _open_output_directory(scratch_fd, name)
        status = os.fstat(cleanup_fd)
        if not stat.S_ISDIR(status.st_mode) or (status.st_dev, status.st_ino) != expected_identity:
            raise OSError("snapshot cleanup target changed")
        _clear_output_directory(cleanup_fd)
        name = _find_snapshot_name(scratch_fd, expected_identity)
        if name is None:
            raise OSError("snapshot cleanup parent changed")
        current_fd = _open_output_directory(scratch_fd, name)
        try:
            current = os.fstat(current_fd)
            if (current.st_dev, current.st_ino) != expected_identity:
                raise OSError("snapshot cleanup target changed")
            with os.scandir(current_fd) as iterator:
                if next(iterator, None) is not None:
                    raise OSError("snapshot cleanup target not empty")
            os.rmdir(name, dir_fd=scratch_fd)
        finally:
            os.close(current_fd)
        if _find_snapshot_name(scratch_fd, expected_identity) is not None:
            raise OSError("snapshot cleanup incomplete")
    finally:
        if cleanup_fd is not None:
            os.close(cleanup_fd)


def _find_snapshot_name(scratch_fd: int, expected_identity: tuple[int, int]) -> str | None:
    with os.scandir(scratch_fd) as iterator:
        names = sorted(entry.name for entry in iterator)
    found: str | None = None
    for name in names:
        try:
            status = os.stat(name, dir_fd=scratch_fd, follow_symlinks=False)
        except FileNotFoundError:
            continue
        if stat.S_ISDIR(status.st_mode) and (status.st_dev, status.st_ino) == expected_identity:
            if found is not None:
                raise OSError("duplicate snapshot cleanup target")
            found = name
    return found


def _clear_output_directory(directory_fd: int) -> None:
    for _attempt in range(8):
        with os.scandir(directory_fd) as iterator:
            names = sorted(entry.name for entry in iterator)
        if not names:
            return
        for name in names:
            status = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
            if stat.S_ISDIR(status.st_mode):
                child_fd = _open_output_directory(directory_fd, name)
                try:
                    child_identity = (status.st_dev, status.st_ino)
                    actual = os.fstat(child_fd)
                    if (actual.st_dev, actual.st_ino) != child_identity:
                        raise OSError("snapshot cleanup directory changed")
                    _clear_output_directory(child_fd)
                    current = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
                    actual = os.fstat(child_fd)
                    if (
                        not stat.S_ISDIR(current.st_mode)
                        or (current.st_dev, current.st_ino) != child_identity
                        or (actual.st_dev, actual.st_ino) != child_identity
                    ):
                        raise OSError("snapshot cleanup directory changed")
                    os.rmdir(name, dir_fd=directory_fd)
                finally:
                    os.close(child_fd)
            else:
                os.unlink(name, dir_fd=directory_fd)
    raise OSError("snapshot cleanup did not quiesce")


def _category(error: Exception) -> str:
    if isinstance(error, UnicodeError):
        return "invalid_manifest"
    return "invalid_local_profile"
