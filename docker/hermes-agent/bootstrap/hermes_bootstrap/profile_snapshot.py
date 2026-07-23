"""Build immutable, allowlisted local profile projections for publication."""

from __future__ import annotations

import ctypes
import errno
import hashlib
import os
import re
import resource
import secrets
import stat
from collections.abc import Iterator
from contextlib import ExitStack
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Literal

import yaml

from . import distributions
from .errors import RepositoryError
from .filesystem import (
    create_private_directory,
    open_absolute_directory,
    verify_absolute_directory,
)
from .models import BootstrapManifest, DistributionSource


ProfileMode = Literal[0o644, 0o755]

_DECLARATIVE_KEYS = (
    "name", "version", "description", "hermes_requires", "author",
    "license", "env_requires", "distribution_owned",
)
_RUNTIME_KEYS = frozenset({"source", "installed_at"})
_READ_CHUNK_BYTES = 64 * 1024
_FD_OPERATION_HEADROOM = 32
_FD_CONSERVATIVE_MARGIN = 32
_RENAME_NOREPLACE = 1
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
_PRIVATE_KEY_CARRY_BYTES = max(len(header) for header in _PRIVATE_KEY_HEADERS) - 1
_ASCII_ALNUM = frozenset(
    b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
)
_ASCII_WORD = _ASCII_ALNUM | frozenset(b"_")
_SLACK_BODY = _ASCII_ALNUM | frozenset(b"-")
_SLACK_CONTINUATION = _SLACK_BODY | frozenset(b"_")
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
    {"auth", "credential", "credentials", "secret", "secrets", "token", "tokens"}
)
_ENV_TEMPLATE = PurePosixPath(".env.template")
_INSTALLED_ENV_EXAMPLE = PurePosixPath(".env.EXAMPLE")


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


class _FdBudgetError(Exception):
    pass


@dataclass(frozen=True)
class _TokenRule:
    prefix: bytes
    body: frozenset[int]
    minimum: int
    trailing_forbidden: frozenset[int]


@dataclass(frozen=True)
class _ExpectedFile:
    path: PurePosixPath
    mode: ProfileMode
    size: int
    sha256: str
    device: int
    inode: int
    descriptor: int


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


_GITHUB_TOKEN_RULES = tuple(
    _TokenRule(prefix, _ASCII_ALNUM, 20, _ASCII_WORD)
    for prefix in (b"ghp_", b"gho_", b"ghu_", b"ghs_", b"ghr_")
) + (_TokenRule(b"github_pat_", _ASCII_WORD, 20, _ASCII_WORD),)
_SLACK_TOKEN_RULES = tuple(
    _TokenRule(prefix, _SLACK_BODY, 1, _SLACK_CONTINUATION)
    for prefix in (b"xoxb-", b"xoxp-", b"xoxa-", b"xoxr-", b"xoxs-", b"xapp-")
)


@dataclass
class _RetainedFdBudget:
    soft_limit: int
    initial_open: int
    tree_depth: int = 0

    @classmethod
    def from_process(cls) -> _RetainedFdBudget:
        try:
            soft_limit, _hard_limit = resource.getrlimit(resource.RLIMIT_NOFILE)
            if soft_limit == resource.RLIM_INFINITY:
                soft_limit = os.sysconf("SC_OPEN_MAX")
        except (OSError, ValueError):
            raise _FdBudgetError from None
        if not isinstance(soft_limit, int) or soft_limit <= 0:
            raise _FdBudgetError
        return cls(soft_limit, _open_descriptor_count())

    def require_headroom(self, *, additional: int = 0) -> None:
        current = max(self.initial_open, _open_descriptor_count())
        reserved = (
            _FD_OPERATION_HEADROOM
            + _FD_CONSERVATIVE_MARGIN
            + self.tree_depth
        )
        if current + additional + reserved > self.soft_limit:
            raise _FdBudgetError

    def require_tree_depth(self, depth: int) -> None:
        self.tree_depth = max(self.tree_depth, depth)
        self.require_headroom()


class _IncrementalTokenDetector:
    def __init__(self, rules: tuple[_TokenRule, ...]) -> None:
        self._rules = rules
        self._start = bytes((rules[0].prefix[0],))
        self._candidates: tuple[_TokenRule, ...] = ()
        self._prefix_index = 0
        self._active: _TokenRule | None = None
        self._body_length = 0
        self._previous: int | None = None

    def feed(self, content: bytes) -> None:
        index = 0
        while index < len(content):
            if self._active is not None:
                index = self._consume_body(content, index)
                continue
            if self._candidates:
                index = self._consume_prefix(content, index)
                continue
            candidate = content.find(self._start, index)
            if candidate < 0:
                self._previous = content[-1]
                return
            previous = content[candidate - 1] if candidate else self._previous
            byte = content[candidate]
            self._previous = byte
            index = candidate + 1
            if previous is None or previous not in _ASCII_WORD:
                self._candidates = self._rules
                self._prefix_index = 1

    def finish(self) -> None:
        if (
            self._active is not None
            and self._body_length >= self._active.minimum
        ):
            raise ValueError("secret candidate")

    def _consume_prefix(self, content: bytes, index: int) -> int:
        previous = self._previous
        byte = content[index]
        next_index = self._prefix_index + 1
        candidates = tuple(
            rule
            for rule in self._candidates
            if len(rule.prefix) >= next_index
            and rule.prefix[self._prefix_index] == byte
        )
        self._previous = byte
        if not candidates:
            self._candidates = ()
            self._prefix_index = 0
            if (
                byte == self._start[0]
                and (previous is None or previous not in _ASCII_WORD)
            ):
                self._candidates = self._rules
                self._prefix_index = 1
            return index + 1
        complete = tuple(rule for rule in candidates if len(rule.prefix) == next_index)
        if complete:
            self._active = complete[0]
            self._body_length = 0
            self._candidates = ()
            self._prefix_index = 0
        else:
            self._candidates = candidates
            self._prefix_index = next_index
        return index + 1

    def _consume_body(self, content: bytes, index: int) -> int:
        assert self._active is not None
        end = index
        while end < len(content) and content[end] in self._active.body:
            end += 1
        if end > index:
            self._body_length = min(
                self._active.minimum, self._body_length + end - index
            )
            self._previous = content[end - 1]
            if end == len(content):
                return end
        next_byte = content[end]
        if (
            self._body_length >= self._active.minimum
            and next_byte not in self._active.trailing_forbidden
        ):
            raise ValueError("secret candidate")
        self._active = None
        self._body_length = 0
        return end


class _SensitiveStreamScanner:
    def __init__(self) -> None:
        self._github = _IncrementalTokenDetector(_GITHUB_TOKEN_RULES)
        self._slack = _IncrementalTokenDetector(_SLACK_TOKEN_RULES)
        self._private_tail = b""

    def feed(self, content: bytes) -> None:
        self._github.feed(content)
        self._slack.feed(content)
        private_window = self._private_tail + content
        if any(header in private_window for header in _PRIVATE_KEY_HEADERS):
            raise ValueError("secret candidate")
        self._private_tail = private_window[-_PRIVATE_KEY_CARRY_BYTES:]

    def finish(self) -> None:
        self._github.finish()
        self._slack.finish()


def _open_descriptor_count() -> int:
    try:
        return len(os.listdir("/proc/self/fd"))
    except OSError:
        raise _FdBudgetError from None


def prepare_profile_snapshots(
    manifest: BootstrapManifest, scratch_root: Path, *, allow_missing: bool
) -> PreparedProfiles:
    """Copy every valid installed profile to caller-owned private scratch space."""

    _require_private_scratch(scratch_root)
    profile = manifest.profiles[0].name if manifest.profiles else "local-profiles"
    try:
        fd_budget = _RetainedFdBudget.from_process()
        fd_budget.require_headroom(additional=1)
    except _FdBudgetError:
        raise ProfileSnapshotError(profile, "resource_limit") from None
    try:
        scratch_fd = open_absolute_directory(scratch_root)
    except OSError as error:
        if error.errno in {errno.EMFILE, errno.ENFILE}:
            raise ProfileSnapshotError(profile, "resource_limit") from None
        raise ValueError("scratch unavailable") from None
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
                try:
                    _validate_profile_name(declaration.name)
                except Exception:
                    raise ProfileSnapshotError(
                        declaration.name, "invalid_profile_name"
                    ) from None
                if declaration.target != manifest.data_root / "profiles" / declaration.name:
                    raise ProfileSnapshotError(declaration.name, "invalid_profile_target")
                if not _path_exists(declaration.target):
                    if allow_missing:
                        missing.append(declaration)
                        continue
                    raise ProfileSnapshotError(declaration.name, "missing_profile")
                fd_budget.require_headroom()
                item = _prepare_one(
                    declaration, scratch_root, scratch_fd, fd_budget
                )
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
        for item in prepared:
            try:
                _final_attest_prepared_snapshot(scratch_root, scratch_fd, item)
            except Exception as error:
                raise ProfileSnapshotError(item.snapshot.declaration.name, _category(error)) from None
        try:
            _verify_scratch_root(scratch_root, scratch_fd)
        except Exception as error:
            profile = manifest.profiles[-1].name if manifest.profiles else "local-profiles"
            raise ProfileSnapshotError(profile, _category(error)) from None
    except ProfileSnapshotError:
        cleanup_profile: str | None = None
        for item in reversed(prepared):
            try:
                _remove_snapshot(
                    scratch_fd,
                    item.output_fd,
                    item.output_identity,
                    item.files,
                    item.directories,
                )
            except Exception:
                if cleanup_profile is None:
                    cleanup_profile = item.snapshot.declaration.name
        if cleanup_profile is not None:
            raise ProfileSnapshotError(cleanup_profile, "cleanup_failed") from None
        raise
    finally:
        try:
            for item in prepared:
                _close_expected_file_descriptors(item.files)
        finally:
            try:
                for item in prepared:
                    os.close(item.output_fd)
            finally:
                os.close(scratch_fd)
    return PreparedProfiles(tuple(item.snapshot for item in prepared), tuple(missing))


def revalidate_profile_snapshots(
    manifest: BootstrapManifest,
    baseline: PreparedProfiles,
    scratch_parent: Path,
) -> None:
    """Reject any local profile projection that changed after preflight."""

    fallback = manifest.profiles[0].name if manifest.profiles else "local-profiles"
    comparison = None
    changed_profile: str | None = None
    category: str | None = None
    try:
        comparison = create_private_directory(
            scratch_parent,
            prefix=".profile-revalidate-",
        )
        try:
            current = prepare_profile_snapshots(
                manifest,
                comparison.path,
                allow_missing=True,
            )
        except ProfileSnapshotError as error:
            changed_profile = error.profile
            category = (
                "cleanup_failed"
                if error.category == "cleanup_failed"
                else "local_profile_changed"
            )
        else:
            if _prepared_fingerprint(current) != _prepared_fingerprint(baseline):
                changed_profile = _first_changed_profile(
                    manifest,
                    baseline,
                    current,
                )
                category = "local_profile_changed"
    except ProfileSnapshotError:
        raise
    except Exception:
        changed_profile = fallback
        category = "local_profile_changed"
    finally:
        if comparison is not None and not comparison.cleanup():
            changed_profile = changed_profile or fallback
            category = "cleanup_failed"
    if category is not None:
        raise ProfileSnapshotError(changed_profile or fallback, category) from None


def _prepared_fingerprint(
    prepared: PreparedProfiles,
) -> object:
    return (
        tuple(
            (
                snapshot.declaration.name,
                snapshot.manifest_bytes,
                snapshot.gitignore_bytes,
                snapshot.entries,
                snapshot.digest,
            )
            for snapshot in prepared.snapshots
        ),
        tuple(source.name for source in prepared.missing),
    )


def _first_changed_profile(
    manifest: BootstrapManifest,
    baseline: PreparedProfiles,
    current: PreparedProfiles,
) -> str:
    for declaration in manifest.profiles:
        if _profile_fingerprint(baseline, declaration.name) != _profile_fingerprint(
            current,
            declaration.name,
        ):
            return declaration.name
    return manifest.profiles[0].name if manifest.profiles else "local-profiles"


def _profile_fingerprint(prepared: PreparedProfiles, name: str) -> object:
    for snapshot in prepared.snapshots:
        if snapshot.declaration.name == name:
            return (
                "snapshot",
                snapshot.manifest_bytes,
                snapshot.gitignore_bytes,
                snapshot.entries,
                snapshot.digest,
            )
    if any(source.name == name for source in prepared.missing):
        return ("missing",)
    return ("absent",)


def _prepare_one(
    declaration: DistributionSource,
    scratch_root: Path,
    scratch_fd: int,
    fd_budget: _RetainedFdBudget,
) -> _PreparedSnapshot:
    output = scratch_root / declaration.name
    try:
        os.stat(declaration.name, dir_fd=scratch_fd, follow_symlinks=False)
    except FileNotFoundError:
        pass
    else:
        raise ValueError("snapshot output already exists")
    output_fd: int | None = None
    output_identity: tuple[int, int] | None = None
    output_created = False
    keep_output_open = False
    keep_expected_files_open = False
    expected_files: list[_ExpectedFile] = []
    expected_directories: dict[PurePosixPath, _ExpectedDirectory] = {}
    source_fd = open_absolute_directory(declaration.target)
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
        _write_private_file_at(
            output_fd,
            "distribution.yaml",
            manifest_bytes,
            0o644,
            expected_files,
            fd_budget,
        )
        entries: list[SnapshotEntry] = []
        casefolded = {
            ".gitignore".casefold(): ".gitignore",
            "distribution.yaml".casefold(): "distribution.yaml",
        }
        directory_paths: set[PurePosixPath] = set()
        for owned_path in owned:
            entry_count = len(entries)
            if owned_path == _ENV_TEMPLATE:
                _copy_installed_env_template(
                    source_fd,
                    output_fd,
                    entries,
                    expected_files,
                    casefolded,
                    fd_budget,
                )
                is_directory = False
            else:
                is_directory = _copy_declared_path(
                    source_fd,
                    owned_path,
                    output_fd,
                    entries,
                    expected_files,
                    expected_directories,
                    casefolded,
                    fd_budget,
                )
            if is_directory:
                if len(entries) == entry_count:
                    raise ProfileSnapshotError(
                        declaration.name,
                        "empty_owned_directory",
                    ) from None
                directory_paths.add(owned_path)
        _validate_canonical_manifest(output_fd, declaration, owned, manifest_bytes)
        _verify_manifest_current(source_fd, manifest_stat)
        verify_absolute_directory(declaration.target, source_fd)
        entries.sort(key=lambda entry: entry.path.as_posix())
        gitignore_bytes = _render_gitignore(owned, frozenset(directory_paths))
        _write_private_file_at(
            output_fd,
            ".gitignore",
            gitignore_bytes,
            0o644,
            expected_files,
            fd_budget,
        )
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
        keep_expected_files_open = True
        return result
    except Exception:
        if output_created:
            if output_identity is None:
                raise ProfileSnapshotError(declaration.name, "cleanup_failed") from None
            try:
                _remove_snapshot(
                    scratch_fd,
                    output_fd,
                    output_identity,
                    tuple(expected_files),
                    tuple(expected_directories.values()),
                )
            except Exception:
                raise ProfileSnapshotError(declaration.name, "cleanup_failed") from None
        raise
    finally:
        try:
            os.close(source_fd)
        finally:
            try:
                if not keep_expected_files_open:
                    _close_expected_file_descriptors(expected_files)
            finally:
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
    expected_raw = yaml.load(
        expected_bytes.decode("utf-8"), Loader=distributions._UniqueKeyLoader
    )
    if not isinstance(expected_raw, dict):
        raise ValueError("manifest shape")
    expected_manifest = distributions.profile_distribution.DistributionManifest.from_dict(
        expected_raw
    )
    projection = _descriptor_projection(root_fd)
    parsed_manifest, parsed_owned = distributions._read_profile_manifest_at(
        projection,
        declaration.name,
        require_sources=True,
    )
    if parsed_owned != owned:
        raise ValueError("manifest ownership")
    if _manifest_semantics(parsed_manifest, parsed_owned) != _manifest_semantics(
        expected_manifest, owned
    ):
        raise ValueError("manifest semantics")
    if _read_regular(root_fd, "distribution.yaml")[0] != expected_bytes:
        raise ValueError("manifest changed")


def _manifest_semantics(
    manifest: object, owned: tuple[PurePosixPath, ...]
) -> dict[str, object]:
    serialized = manifest.to_dict()  # type: ignore[attr-defined]
    if not isinstance(serialized, dict):
        raise ValueError("manifest semantics")
    semantics = {key: serialized.get(key) for key in _DECLARATIVE_KEYS}
    semantics["distribution_owned"] = [path.as_posix() for path in owned]
    return semantics


def _normalize_owned(values: object) -> tuple[PurePosixPath, ...]:
    if not isinstance(values, list) or not values:
        raise ValueError("empty ownership")
    for value in values:
        if (
            isinstance(value, str)
            and PurePosixPath(value) == _ENV_TEMPLATE
            and value != _ENV_TEMPLATE.as_posix()
        ):
            raise ValueError("noncanonical env template ownership")
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


def _copy_installed_env_template(
    source_fd: int,
    output_fd: int,
    entries: list[SnapshotEntry],
    expected_files: list[_ExpectedFile],
    casefolded: dict[str, str],
    fd_budget: _RetainedFdBudget,
) -> None:
    source = _stat_exact_installed_env_example(source_fd)
    _check_casefold(_ENV_TEMPLATE, casefolded)
    _copy_regular(
        source_fd,
        _INSTALLED_ENV_EXAMPLE.name,
        _ENV_TEMPLATE,
        output_fd,
        entries,
        expected_files,
        fd_budget,
        destination_name=_ENV_TEMPLATE.name,
        expected_source=source,
    )
    current = _stat_exact_installed_env_example(source_fd)
    if _regular_identity(source) != _regular_identity(current):
        raise ValueError("env template source changed")


def _stat_exact_installed_env_example(source_fd: int) -> os.stat_result:
    matches: list[tuple[str, os.stat_result]] = []
    expected_name = _INSTALLED_ENV_EXAMPLE.name
    with os.scandir(source_fd) as iterator:
        for entry in iterator:
            if entry.name.casefold() == expected_name.casefold():
                matches.append(
                    (entry.name, entry.stat(follow_symlinks=False))
                )
    if len(matches) != 1 or matches[0][0] != expected_name:
        raise ValueError("invalid installed env example spelling")
    source = matches[0][1]
    _require_safe_source(source)
    if not stat.S_ISREG(source.st_mode):
        raise ValueError("unsafe env template source")
    return source


def _copy_declared_path(
    source_fd: int,
    path: PurePosixPath,
    output_fd: int,
    entries: list[SnapshotEntry],
    expected_files: list[_ExpectedFile],
    expected_directories: dict[PurePosixPath, _ExpectedDirectory],
    casefolded: dict[str, str],
    fd_budget: _RetainedFdBudget,
) -> bool:
    with ExitStack() as descriptors:
        source_root_fd = os.dup(source_fd)
        descriptors.callback(os.close, source_root_fd)
        source_fds = [source_root_fd]
        output_root_fd = os.dup(output_fd)
        descriptors.callback(os.close, output_root_fd)
        output_fds = [output_root_fd]
        ancestors: list[
            tuple[int, str, int, tuple[os.stat_result, os.stat_result]]
        ] = []
        prefix = PurePosixPath()
        for component in path.parts[:-1]:
            prefix /= component
            fd_budget.require_tree_depth(len(prefix.parts))
            source_child_fd, source_identity = _open_source_directory(source_fds[-1], component)
            descriptors.callback(os.close, source_child_fd)
            output_child_fd = _create_output_directory(
                output_fds[-1],
                component,
                prefix,
                expected_directories,
            )
            descriptors.callback(os.close, output_child_fd)
            ancestors.append((source_fds[-1], component, source_child_fd, source_identity))
            source_fds.append(source_child_fd)
            output_fds.append(output_child_fd)
        source_parent_fd = source_fds[-1]
        output_parent_fd = output_fds[-1]
        source = os.stat(path.name, dir_fd=source_parent_fd, follow_symlinks=False)
        _require_safe_source(source)
        _check_casefold(path, casefolded)
        if stat.S_ISDIR(source.st_mode):
            fd_budget.require_tree_depth(len(path.parts))
            with ExitStack() as child_descriptors:
                source_child_fd, source_identity = _open_source_directory(
                    source_parent_fd, path.name
                )
                child_descriptors.callback(os.close, source_child_fd)
                output_child_fd = _create_output_directory(
                    output_parent_fd,
                    path.name,
                    path,
                    expected_directories,
                )
                child_descriptors.callback(os.close, output_child_fd)
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
                    fd_budget,
                )
            result = True
        else:
            _copy_regular(
                source_parent_fd,
                path.name,
                path,
                output_parent_fd,
                entries,
                expected_files,
                fd_budget,
            )
            result = False
        for parent_fd, name, descriptor, identity in reversed(ancestors):
            _verify_source_directory(parent_fd, name, descriptor, identity)
        return result


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
    fd_budget: _RetainedFdBudget,
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
            fd_budget.require_tree_depth(len(relative.parts))
            with ExitStack() as child_descriptors:
                source_child_fd, child_identity = _open_source_directory(
                    source_fd, name
                )
                child_descriptors.callback(os.close, source_child_fd)
                output_child_fd = _create_output_directory(
                    output_fd,
                    name,
                    relative,
                    expected_directories,
                )
                child_descriptors.callback(os.close, output_child_fd)
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
                    fd_budget,
                )
        else:
            _copy_regular(
                source_fd,
                name,
                relative,
                output_fd,
                entries,
                expected_files,
                fd_budget,
            )
    _verify_source_directory(source_parent_fd, source_name, source_fd, source_identity)


def _copy_regular(
    parent_fd: int,
    name: str,
    relative: PurePosixPath,
    output_fd: int,
    entries: list[SnapshotEntry],
    expected_files: list[_ExpectedFile],
    fd_budget: _RetainedFdBudget,
    *,
    destination_name: str | None = None,
    expected_source: os.stat_result | None = None,
) -> None:
    destination_fd: int | None = None
    destination_registered = False
    output_name = destination_name if destination_name is not None else name
    source_fd = _open_regular(
        parent_fd,
        name,
        expected_source=expected_source,
    )
    try:
        before = os.fstat(source_fd)
        fd_budget.require_headroom(additional=1)
        destination_fd = os.open(output_name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC, 0o600, dir_fd=output_fd)
        created = os.fstat(destination_fd)
        expected_index = len(expected_files)
        expected_files.append(
            _ExpectedFile(
                relative,
                0o644,
                0,
                "",
                created.st_dev,
                created.st_ino,
                destination_fd,
            )
        )
        destination_registered = True
        digest = hashlib.sha256()
        size = 0
        scanner = _SensitiveStreamScanner()
        for chunk in _read_bounded_chunks(source_fd, before.st_size):
            _reject_sensitive_bytes(chunk, final=False, scanner=scanner)
            _write_descriptor(destination_fd, chunk)
            digest.update(chunk)
            size += len(chunk)
        _reject_sensitive_bytes(b"", scanner=scanner)
        _verify_regular(parent_fd, name, source_fd, before, size)
        mode = _git_mode(before.st_mode)
        os.fchmod(destination_fd, mode)
        os.fsync(destination_fd)
        destination = _verify_destination_descriptor(
            output_fd,
            output_name,
            destination_fd,
            mode,
            size,
        )
        sha256 = digest.hexdigest()
        expected_files[expected_index] = _ExpectedFile(
            relative,
            mode,
            size,
            sha256,
            destination.st_dev,
            destination.st_ino,
            destination_fd,
        )
    finally:
        os.close(source_fd)
        if destination_fd is not None and not destination_registered:
            os.close(destination_fd)
    entries.append(SnapshotEntry(relative, mode, size, sha256))


def _read_regular(parent_fd: int, name: str) -> tuple[bytes, os.stat_result]:
    descriptor = _open_regular(parent_fd, name)
    try:
        before = os.fstat(descriptor)
        chunks = list(_read_bounded_chunks(descriptor, before.st_size))
        content = b"".join(chunks)
        _verify_regular(parent_fd, name, descriptor, before, len(content))
        return content, before
    finally:
        os.close(descriptor)


def _read_bounded_chunks(descriptor: int, expected_size: int) -> Iterator[bytes]:
    remaining = expected_size
    while remaining:
        chunk = os.read(descriptor, min(_READ_CHUNK_BYTES, remaining))
        if not chunk:
            raise ValueError("file changed while reading")
        remaining -= len(chunk)
        yield chunk
    if os.read(descriptor, 1):
        raise ValueError("file changed while reading")


def _open_regular(
    parent_fd: int,
    name: str,
    *,
    expected_source: os.stat_result | None = None,
) -> int:
    flags = (
        os.O_RDONLY
        | os.O_CLOEXEC
        | getattr(os, "O_NOFOLLOW", 0)
        | getattr(os, "O_NONBLOCK", 0)
    )
    descriptor = os.open(name, flags, dir_fd=parent_fd)
    try:
        source = os.fstat(descriptor)
        _require_safe_source(source)
        if (
            expected_source is not None
            and _regular_identity(source) != _regular_identity(expected_source)
        ):
            raise ValueError("source replaced before open")
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
    flags = (
        os.O_RDONLY
        | os.O_CLOEXEC
        | getattr(os, "O_DIRECTORY", 0)
        | getattr(os, "O_NOFOLLOW", 0)
        | getattr(os, "O_NONBLOCK", 0)
    )
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
    expected_files: list[_ExpectedFile],
    fd_budget: _RetainedFdBudget,
) -> _ExpectedFile:
    fd_budget.require_headroom(additional=1)
    registered = False
    descriptor = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC, 0o600, dir_fd=parent_fd)
    try:
        created = os.fstat(descriptor)
        expected_index = len(expected_files)
        expected_files.append(
            _ExpectedFile(
                PurePosixPath(name),
                mode,
                0,
                "",
                created.st_dev,
                created.st_ino,
                descriptor,
            )
        )
        registered = True
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
        expected = _ExpectedFile(
            PurePosixPath(name),
            mode,
            len(content),
            hashlib.sha256(content).hexdigest(),
            status.st_dev,
            status.st_ino,
            descriptor,
        )
        expected_files[expected_index] = expected
        return expected
    finally:
        if not registered:
            os.close(descriptor)


def _close_expected_file_descriptors(files: tuple[_ExpectedFile, ...] | list[_ExpectedFile]) -> None:
    first_error: OSError | None = None
    for expected in files:
        try:
            os.close(expected.descriptor)
        except OSError as error:
            if first_error is None:
                first_error = error
    if first_error is not None:
        raise first_error


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
    _verify_prepared_snapshot_passes(scratch_root, scratch_fd, prepared, tree_passes=1)


def _final_attest_prepared_snapshot(
    scratch_root: Path,
    scratch_fd: int,
    prepared: _PreparedSnapshot,
) -> None:
    _verify_prepared_snapshot_passes(scratch_root, scratch_fd, prepared, tree_passes=2)


def _verify_prepared_snapshot_passes(
    scratch_root: Path,
    scratch_fd: int,
    prepared: _PreparedSnapshot,
    *,
    tree_passes: int,
) -> None:
    _require_private_scratch_status(os.fstat(scratch_fd))
    _verify_absolute_directory_nonblocking(scratch_root, scratch_fd)
    _verify_output_root(
        scratch_fd,
        prepared.snapshot.declaration.name,
        prepared.output_fd,
        prepared.output_identity,
    )
    _verify_absolute_directory_nonblocking(prepared.snapshot.root, prepared.output_fd)
    os.fsync(prepared.output_fd)
    for _pass in range(tree_passes):
        _verify_snapshot_tree(prepared.output_fd, prepared.files, prepared.directories)
    _verify_output_root(
        scratch_fd,
        prepared.snapshot.declaration.name,
        prepared.output_fd,
        prepared.output_identity,
    )
    _verify_absolute_directory_nonblocking(prepared.snapshot.root, prepared.output_fd)
    _require_private_scratch_status(os.fstat(scratch_fd))
    _verify_absolute_directory_nonblocking(scratch_root, scratch_fd)


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
    expected_names = {
        path.name
        for path in (*expected_files, *expected_directories)
        if path.parent == prefix
    }
    names = _snapshot_directory_names(directory_fd)
    if set(names) != expected_names:
        raise ValueError("snapshot inventory changed")
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
    if set(_snapshot_directory_names(directory_fd)) != expected_names:
        raise ValueError("snapshot inventory changed")


def _snapshot_directory_names(directory_fd: int) -> list[str]:
    with os.scandir(directory_fd) as iterator:
        return sorted(entry.name for entry in iterator)


def _verify_expected_file(parent_fd: int, name: str, expected: _ExpectedFile) -> None:
    _require_expected_file_status(os.fstat(expected.descriptor), expected)
    descriptor = os.open(
        name,
        os.O_RDONLY
        | os.O_CLOEXEC
        | getattr(os, "O_NOFOLLOW", 0)
        | getattr(os, "O_NONBLOCK", 0),
        dir_fd=parent_fd,
    )
    try:
        before = os.fstat(descriptor)
        _require_expected_file_status(before, expected)
        current = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
        _require_expected_file_status(current, expected)
        digest = hashlib.sha256()
        size = 0
        for chunk in _read_bounded_chunks(descriptor, expected.size):
            digest.update(chunk)
            size += len(chunk)
        after = os.fstat(descriptor)
        _require_expected_file_status(after, expected)
        _require_expected_file_status(os.fstat(expected.descriptor), expected)
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


def _reject_sensitive_bytes(
    content: bytes,
    *,
    final: bool = True,
    scanner: _SensitiveStreamScanner | None = None,
) -> None:
    active_scanner = scanner if scanner is not None else _SensitiveStreamScanner()
    active_scanner.feed(content)
    if final:
        active_scanner.finish()


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


def _verify_scratch_root(path: Path, descriptor: int) -> None:
    _require_private_scratch_status(os.fstat(descriptor))
    _verify_absolute_directory_nonblocking(path, descriptor)


def _verify_absolute_directory_nonblocking(path: Path, descriptor: int) -> None:
    normalized = Path(os.path.normpath(path))
    if not path.is_absolute() or path != normalized or path.anchor != "/":
        raise ValueError("directory path is not canonical")
    flags = (
        os.O_RDONLY
        | os.O_CLOEXEC
        | getattr(os, "O_DIRECTORY", 0)
        | getattr(os, "O_NOFOLLOW", 0)
        | getattr(os, "O_NONBLOCK", 0)
    )
    current_fd: int | None = None
    try:
        current_fd = os.open("/", flags)
        for component in path.parts[1:]:
            child_fd = os.open(component, flags, dir_fd=current_fd)
            try:
                current = os.stat(
                    component, dir_fd=current_fd, follow_symlinks=False
                )
                opened = os.fstat(child_fd)
                if (
                    stat.S_ISLNK(current.st_mode)
                    or not stat.S_ISDIR(opened.st_mode)
                    or (current.st_dev, current.st_ino)
                    != (opened.st_dev, opened.st_ino)
                ):
                    raise ValueError("directory path is unsafe")
            except Exception:
                os.close(child_fd)
                raise
            os.close(current_fd)
            current_fd = child_fd
        expected = os.fstat(descriptor)
        actual = os.fstat(current_fd)
        if (expected.st_dev, expected.st_ino) != (actual.st_dev, actual.st_ino):
            raise ValueError("directory path changed")
    finally:
        if current_fd is not None:
            os.close(current_fd)


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
    files: tuple[_ExpectedFile, ...],
    directories: tuple[_ExpectedDirectory, ...],
) -> None:
    expected_files = {(item.device, item.inode): item for item in files}
    expected_directories = {
        (item.device, item.inode): item for item in directories
    }
    if len(expected_files) != len(files) or len(expected_directories) != len(directories):
        raise OSError("duplicate snapshot cleanup entry")
    for expected_file in files:
        _require_cleanup_retained_file(expected_file)
    file_paths = {item.path for item in files}
    directory_paths = {item.path for item in directories}
    removed_files: set[tuple[int, int]] = set()
    removed_directories: set[tuple[int, int]] = set()
    cleanup_fd: int | None = None
    try:
        if output_fd is not None:
            cleanup_fd = os.dup(output_fd)
        if cleanup_fd is None:
            name = _find_snapshot_name(scratch_fd, expected_identity)
            if name is None:
                raise OSError("snapshot cleanup target unavailable")
            cleanup_fd = _open_output_directory(scratch_fd, name)
        status = os.fstat(cleanup_fd)
        if not stat.S_ISDIR(status.st_mode) or (status.st_dev, status.st_ino) != expected_identity:
            raise OSError("snapshot cleanup target changed")
        clear_failed = False
        try:
            _clear_output_directory(
                cleanup_fd,
                PurePosixPath(),
                expected_files,
                expected_directories,
                file_paths,
                directory_paths,
                removed_files,
                removed_directories,
            )
        except Exception:
            clear_failed = True
        if removed_files != set(expected_files) or removed_directories != set(
            expected_directories
        ):
            clear_failed = True
        with os.scandir(cleanup_fd) as iterator:
            if next(iterator, None) is not None:
                raise OSError("snapshot cleanup target not empty")
        name = _find_snapshot_name(scratch_fd, expected_identity)
        if name is None:
            raise OSError("snapshot cleanup parent changed")
        quarantine, collided = _quarantine_cleanup_entry(
            scratch_fd, name, expected_identity, directory=True
        )
        _delete_quarantined_directory(
            scratch_fd, quarantine, cleanup_fd, expected_identity, collided
        )
        if _find_snapshot_name(scratch_fd, expected_identity) is not None:
            raise OSError("snapshot cleanup incomplete")
        if clear_failed:
            raise OSError("snapshot cleanup inventory changed")
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


def _clear_output_directory(
    directory_fd: int,
    prefix: PurePosixPath,
    expected_files: dict[tuple[int, int], _ExpectedFile],
    expected_directories: dict[tuple[int, int], _ExpectedDirectory],
    file_paths: set[PurePosixPath],
    directory_paths: set[PurePosixPath],
    removed_files: set[tuple[int, int]],
    removed_directories: set[tuple[int, int]],
) -> None:
    with os.scandir(directory_fd) as iterator:
        names = sorted(entry.name for entry in iterator)
    failed = False
    for name in names:
        try:
            expected = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
            identity = (expected.st_dev, expected.st_ino)
            relative = prefix / name
            expected_file = expected_files.get(identity)
            expected_directory = expected_directories.get(identity)
            if expected_file is not None:
                if identity in removed_files:
                    raise OSError("duplicate snapshot cleanup file")
                _remove_cleanup_file(
                    directory_fd, name, identity, expected_file
                )
                removed_files.add(identity)
            elif expected_directory is not None:
                if identity in removed_directories:
                    raise OSError("duplicate snapshot cleanup directory")
                _remove_cleanup_directory(
                    directory_fd,
                    name,
                    identity,
                    expected_directory.path,
                    expected_files,
                    expected_directories,
                    file_paths,
                    directory_paths,
                    removed_files,
                    removed_directories,
                )
                removed_directories.add(identity)
            elif relative in file_paths or relative in directory_paths:
                raise OSError("snapshot cleanup replacement retained")
            elif stat.S_ISDIR(expected.st_mode):
                _remove_cleanup_directory(
                    directory_fd,
                    name,
                    identity,
                    relative,
                    expected_files,
                    expected_directories,
                    file_paths,
                    directory_paths,
                    removed_files,
                    removed_directories,
                )
            elif stat.S_ISREG(expected.st_mode):
                _remove_cleanup_file(directory_fd, name, identity)
            else:
                raise OSError("unsafe snapshot cleanup entry")
        except Exception:
            failed = True
    with os.scandir(directory_fd) as iterator:
        remaining = next(iterator, None) is not None
    if failed or remaining:
        raise OSError("snapshot cleanup did not quiesce")


def _remove_cleanup_directory(
    parent_fd: int,
    name: str,
    expected_identity: tuple[int, int],
    prefix: PurePosixPath,
    expected_files: dict[tuple[int, int], _ExpectedFile],
    expected_directories: dict[tuple[int, int], _ExpectedDirectory],
    file_paths: set[PurePosixPath],
    directory_paths: set[PurePosixPath],
    removed_files: set[tuple[int, int]],
    removed_directories: set[tuple[int, int]],
) -> None:
    child_fd = _open_output_directory(parent_fd, name)
    try:
        actual = os.fstat(child_fd)
        if (actual.st_dev, actual.st_ino) != expected_identity:
            raise OSError("snapshot cleanup directory changed")
        clear_failed = False
        try:
            _clear_output_directory(
                child_fd,
                prefix,
                expected_files,
                expected_directories,
                file_paths,
                directory_paths,
                removed_files,
                removed_directories,
            )
        except Exception:
            clear_failed = True
        with os.scandir(child_fd) as iterator:
            if next(iterator, None) is not None:
                raise OSError("snapshot cleanup directory not empty")
        quarantine, collided = _quarantine_cleanup_entry(
            parent_fd, name, expected_identity, directory=True
        )
        _delete_quarantined_directory(
            parent_fd, quarantine, child_fd, expected_identity, collided
        )
        if clear_failed:
            raise OSError("snapshot cleanup directory changed")
    finally:
        os.close(child_fd)


def _remove_cleanup_file(
    parent_fd: int,
    name: str,
    expected_identity: tuple[int, int],
    expected_file: _ExpectedFile | None = None,
) -> None:
    retained = (
        _require_cleanup_retained_file(expected_file)
        if expected_file is not None
        else None
    )
    flags = (
        os.O_RDWR
        | os.O_CLOEXEC
        | getattr(os, "O_NOFOLLOW", 0)
        | getattr(os, "O_NONBLOCK", 0)
    )
    descriptor = os.open(name, flags, dir_fd=parent_fd)
    try:
        current = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
        actual = os.fstat(descriptor)
        statuses = (current, actual) if retained is None else (current, actual, retained)
        for status in statuses:
            if (
                not stat.S_ISREG(status.st_mode)
                or (status.st_dev, status.st_ino) != expected_identity
            ):
                raise OSError("snapshot cleanup file changed")
        action_descriptor = (
            expected_file.descriptor if expected_file is not None else descriptor
        )
        action_status = (
            _require_cleanup_retained_file(expected_file)
            if expected_file is not None
            else actual
        )
        if action_status.st_nlink == 1:
            os.ftruncate(action_descriptor, 0)
            os.fsync(action_descriptor)
        actual = os.fstat(descriptor)
        statuses = (actual,)
        if expected_file is not None:
            statuses += (_require_cleanup_retained_file(expected_file),)
        for status in statuses:
            if (
                not stat.S_ISREG(status.st_mode)
                or (status.st_dev, status.st_ino) != expected_identity
            ):
                raise OSError("snapshot cleanup file changed")
        quarantine, collided = _quarantine_cleanup_entry(
            parent_fd, name, expected_identity, directory=False
        )
        _delete_quarantined_file(
            parent_fd,
            quarantine,
            action_descriptor,
            expected_identity,
            collided,
        )
    finally:
        os.close(descriptor)


def _require_cleanup_retained_file(expected: _ExpectedFile) -> os.stat_result:
    status = os.fstat(expected.descriptor)
    if (
        not stat.S_ISREG(status.st_mode)
        or (status.st_dev, status.st_ino) != (expected.device, expected.inode)
    ):
        raise OSError("snapshot cleanup file changed")
    return status


def _delete_quarantined_file(
    parent_fd: int,
    name: str,
    descriptor: int,
    expected_identity: tuple[int, int],
    collided: bool,
) -> None:
    _delete_after_atomic_transfer(
        parent_fd,
        name,
        descriptor,
        expected_identity,
        directory=False,
        collided=collided,
    )


def _delete_quarantined_directory(
    parent_fd: int,
    name: str,
    descriptor: int,
    expected_identity: tuple[int, int],
    collided: bool,
) -> None:
    _delete_after_atomic_transfer(
        parent_fd,
        name,
        descriptor,
        expected_identity,
        directory=True,
        collided=collided,
    )


def _delete_after_atomic_transfer(
    parent_fd: int,
    name: str,
    descriptor: int,
    expected_identity: tuple[int, int],
    *,
    directory: bool,
    collided: bool,
) -> None:
    final_name, final_collision = _quarantine_cleanup_entry(
        parent_fd, name, expected_identity, directory=directory
    )
    current = os.stat(final_name, dir_fd=parent_fd, follow_symlinks=False)
    actual = os.fstat(descriptor)
    for status in (current, actual):
        if (
            stat.S_ISDIR(status.st_mode) != directory
            or (status.st_dev, status.st_ino) != expected_identity
        ):
            raise OSError("snapshot cleanup entry changed")
    if directory:
        os.rmdir(final_name, dir_fd=parent_fd)
    else:
        os.unlink(final_name, dir_fd=parent_fd)
    if collided or final_collision:
        raise OSError("snapshot cleanup quarantine collision")


def _quarantine_cleanup_entry(
    parent_fd: int,
    name: str,
    expected_identity: tuple[int, int],
    *,
    directory: bool,
) -> tuple[str, bool]:
    collided = False
    for _attempt in range(16):
        quarantine = _unused_cleanup_name(parent_fd)
        try:
            _rename_noreplace_at(parent_fd, name, parent_fd, quarantine)
        except FileExistsError:
            collided = True
            continue
        current = os.stat(quarantine, dir_fd=parent_fd, follow_symlinks=False)
        if (
            stat.S_ISDIR(current.st_mode) != directory
            or (current.st_dev, current.st_ino) != expected_identity
        ):
            try:
                _rename_noreplace_at(parent_fd, quarantine, parent_fd, name)
            except OSError:
                pass
            raise OSError("snapshot cleanup entry changed")
        return quarantine, collided
    raise OSError("snapshot cleanup quarantine collision")


def _rename_noreplace_at(
    source_fd: int,
    source_name: str,
    destination_fd: int,
    destination_name: str,
) -> None:
    try:
        renameat2 = ctypes.CDLL(None, use_errno=True).renameat2
    except (AttributeError, OSError):
        raise OSError(errno.ENOSYS, "atomic no-replace rename unavailable") from None
    renameat2.argtypes = (
        ctypes.c_int,
        ctypes.c_char_p,
        ctypes.c_int,
        ctypes.c_char_p,
        ctypes.c_uint,
    )
    renameat2.restype = ctypes.c_int
    ctypes.set_errno(0)
    result = renameat2(
        source_fd,
        os.fsencode(source_name),
        destination_fd,
        os.fsencode(destination_name),
        _RENAME_NOREPLACE,
    )
    if result == 0:
        return
    error_number = ctypes.get_errno() or errno.EIO
    unsupported = {
        errno.ENOSYS,
        errno.EINVAL,
        getattr(errno, "ENOTSUP", errno.EINVAL),
        getattr(errno, "EOPNOTSUPP", errno.EINVAL),
    }
    if error_number in unsupported:
        raise OSError(
            error_number, "atomic no-replace rename unavailable"
        ) from None
    raise OSError(error_number, "atomic no-replace rename failed") from None


def _unused_cleanup_name(parent_fd: int) -> str:
    for _attempt in range(16):
        candidate = f".snapshot-cleanup-{secrets.token_hex(16)}"
        try:
            os.stat(candidate, dir_fd=parent_fd, follow_symlinks=False)
        except FileNotFoundError:
            return candidate
    raise OSError("snapshot cleanup quarantine unavailable")


def _category(error: Exception) -> str:
    if isinstance(error, _FdBudgetError):
        return "resource_limit"
    if isinstance(error, UnicodeError):
        return "invalid_manifest"
    return "invalid_local_profile"
