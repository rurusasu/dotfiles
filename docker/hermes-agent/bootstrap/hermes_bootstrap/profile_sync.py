"""Publish exact local Hermes profile snapshots with Git plumbing."""

from __future__ import annotations

import hashlib
import os
import re
import shutil
import stat
import tempfile
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Literal

from .git import (
    _create_askpass,
    _git_environment,
    _remote_identity,
    _run_git_bytes,
    _same_remote_identity,
    _valid_auth,
    _valid_ref,
)
from .github import GitAuth
from .models import BootstrapManifest, DistributionSource
from .profile_snapshot import (
    PreparedProfiles,
    ProfileSnapshot,
    ProfileSnapshotError,
    prepare_profile_snapshots,
)
from .repositories import _LockBusy, _RepositoryLock


SyncStatus = Literal["changed", "unchanged", "failed"]

_OBJECT_ID = re.compile(rb"[0-9a-fA-F]{40}(?:[0-9a-fA-F]{24})?\Z")
_COMMAND_OUTPUT_MAX_BYTES = 64 * 1024
_INDEX_OUTPUT_MAX_BYTES = 8 * 1024 * 1024
_REPOSITORY_EXIT_CODE = 4


@dataclass(frozen=True)
class ProfileDiff:
    added: tuple[PurePosixPath, ...] = ()
    modified: tuple[PurePosixPath, ...] = ()
    deleted: tuple[PurePosixPath, ...] = ()


@dataclass(frozen=True)
class ProfileSyncResult:
    name: str
    status: SyncStatus
    commit: str | None
    snapshot: str
    diff: ProfileDiff
    category: str
    message: str

    def as_dict(self) -> dict[str, object]:
        added = [path.as_posix() for path in self.diff.added]
        modified = [path.as_posix() for path in self.diff.modified]
        deleted = [path.as_posix() for path in self.diff.deleted]
        return {
            "name": self.name,
            "status": self.status,
            "commit": self.commit,
            "snapshot": self.snapshot,
            "added": added,
            "modified": modified,
            "deleted": deleted,
            "paths": sorted((*added, *modified, *deleted)),
            "category": self.category,
            "message": self.message,
        }


@dataclass(frozen=True)
class ProfileSyncReport:
    dry_run: bool
    profiles: tuple[ProfileSyncResult, ...]
    exit_code: int

    def as_dict(self) -> dict[str, object]:
        if self.exit_code != 0 or any(
            profile.status == "failed" for profile in self.profiles
        ):
            status: SyncStatus = "failed"
        elif any(profile.status == "changed" for profile in self.profiles):
            status = "changed"
        else:
            status = "unchanged"
        return {
            "schema_version": 1,
            "command": "sync-profiles",
            "dry_run": self.dry_run,
            "status": status,
            "profiles": [profile.as_dict() for profile in self.profiles],
        }


@dataclass(frozen=True)
class _Attempt:
    remote_commit: str
    tree: str


class _PushRejected(Exception):
    pass


class _PushRaceExhausted(Exception):
    pass


def failed_profile_report(
    profiles: tuple[DistributionSource, ...],
    *,
    dry_run: bool,
    category: str,
    message: str,
    exit_code: int,
) -> ProfileSyncReport:
    return ProfileSyncReport(
        dry_run=dry_run,
        profiles=tuple(
            ProfileSyncResult(
                name=profile.name,
                status="failed",
                commit=None,
                snapshot="",
                diff=ProfileDiff(),
                category=category,
                message=message,
            )
            for profile in profiles
        ),
        exit_code=exit_code,
    )


def synchronize_prepared_profiles(
    prepared: PreparedProfiles, auth: GitAuth, *, dry_run: bool
) -> ProfileSyncReport:
    """Synchronize each immutable profile projection in prepared order."""

    if not isinstance(prepared, PreparedProfiles):
        return ProfileSyncReport(dry_run, (), _REPOSITORY_EXIT_CODE)
    if prepared.missing:
        declarations = (
            *(snapshot.declaration for snapshot in prepared.snapshots),
            *prepared.missing,
        )
        return failed_profile_report(
            declarations,
            dry_run=dry_run,
            category="aggregate_preflight_blocked",
            message="profile snapshot preparation is incomplete",
            exit_code=_REPOSITORY_EXIT_CODE,
        )
    results = tuple(
        _synchronize_one_boundary(snapshot, auth, dry_run)
        for snapshot in prepared.snapshots
    )
    exit_code = (
        _REPOSITORY_EXIT_CODE
        if any(item.status == "failed" for item in results)
        else 0
    )
    return ProfileSyncReport(dry_run, results, exit_code)


def synchronize_profiles(
    manifest: BootstrapManifest, auth: GitAuth, *, dry_run: bool
) -> ProfileSyncReport:
    """Prepare and publish every configured profile from private scratch."""

    profiles = manifest.profiles if isinstance(manifest, BootstrapManifest) else ()
    scratch: Path | None = None
    report: ProfileSyncReport
    try:
        _validate_manifest_profiles(manifest)
        scratch = Path(
            tempfile.mkdtemp(prefix=".hermes-profile-snapshots-", dir=manifest.data_root)
        )
        os.chmod(scratch, 0o700)
        prepared = prepare_profile_snapshots(manifest, scratch, allow_missing=False)
        report = synchronize_prepared_profiles(prepared, auth, dry_run=dry_run)
    except ProfileSnapshotError as error:
        report = _profile_preflight_failure(
            profiles, error.profile, error.category, dry_run=dry_run
        )
    except Exception:
        report = failed_profile_report(
            profiles,
            dry_run=dry_run,
            category="aggregate_preflight_blocked",
            message="profile snapshot preflight failed",
            exit_code=_REPOSITORY_EXIT_CODE,
        )
    cleanup_failed = _cleanup_resources(
        ((_remove_tree, scratch),) if scratch is not None else ()
    )
    if cleanup_failed:
        return failed_profile_report(
            profiles,
            dry_run=dry_run,
            category="cleanup_failed",
            message="could not clean private profile snapshot resources",
            exit_code=_REPOSITORY_EXIT_CODE,
        )
    return report


def _validate_manifest_profiles(manifest: BootstrapManifest) -> None:
    if (
        not isinstance(manifest, BootstrapManifest)
        or not manifest.data_root.is_absolute()
        or not _safe_directory(manifest.data_root)
        or any(
            profile.target
            != manifest.data_root / "profiles" / profile.name
            for profile in manifest.profiles
        )
    ):
        raise ValueError("invalid profile manifest")


def _profile_preflight_failure(
    profiles: tuple[DistributionSource, ...],
    invalid_name: str,
    invalid_category: str,
    *,
    dry_run: bool,
) -> ProfileSyncReport:
    results = tuple(
        ProfileSyncResult(
            name=profile.name,
            status="failed",
            commit=None,
            snapshot="",
            diff=ProfileDiff(),
            category=(
                invalid_category
                if profile.name == invalid_name
                else "aggregate_preflight_blocked"
            ),
            message=(
                "local profile snapshot is invalid"
                if profile.name == invalid_name
                else "profile publication blocked by aggregate preflight"
            ),
        )
        for profile in profiles
    )
    return ProfileSyncReport(dry_run, results, _REPOSITORY_EXIT_CODE)


def _synchronize_one_boundary(
    snapshot: ProfileSnapshot, auth: GitAuth, dry_run: bool
) -> ProfileSyncResult:
    declaration = snapshot.declaration
    data_root = declaration.target.parent.parent
    lock_path = data_root / "locks" / "repositories" / f"profile-{declaration.name}.lock"
    repository: Path | None = None
    askpass: Path | None = None
    try:
        _validate_snapshot_declaration(snapshot, auth, data_root)
        with _RepositoryLock(lock_path, data_root) as repository_lock:
            repository_lock.require_held()
            repository = Path(tempfile.mkdtemp(prefix=".hermes-profile-sync-", dir=data_root))
            os.chmod(repository, 0o700)
            askpass = _create_askpass(data_root)
            environment = _git_environment(auth, askpass)
            attempt = _exact_tree_attempt(snapshot, repository, environment)
            repository_lock.require_held()
            remote_tree = _git_ascii(
                ("rev-parse", "FETCH_HEAD^{tree}"), repository, environment
            )
            if remote_tree is None:
                raise ValueError("remote tree unavailable")
            if attempt.tree == remote_tree:
                outcome = ProfileSyncResult(
                    name=declaration.name,
                    status="unchanged",
                    commit=attempt.remote_commit,
                    snapshot=snapshot.digest,
                    diff=ProfileDiff(),
                    category="unchanged",
                    message="profile snapshot already published",
                )
            else:
                diff = _profile_diff(
                    repository, environment, auth, attempt.remote_commit
                )
                if dry_run:
                    commit = attempt.remote_commit
                    category = "dry_run"
                    message = "profile snapshot changes detected"
                else:
                    commit, final_parent = _commit_and_push(
                        snapshot, attempt, repository, environment
                    )
                    if final_parent != attempt.remote_commit:
                        diff = _profile_diff(
                            repository, environment, auth, final_parent
                        )
                    category = "published"
                    message = "profile snapshot published"
                outcome = ProfileSyncResult(
                    name=declaration.name,
                    status="changed",
                    commit=commit,
                    snapshot=snapshot.digest,
                    diff=diff,
                    category=category,
                    message=message,
                )
    except _LockBusy:
        outcome = _failed(snapshot, "lock_busy", "profile publication lock is busy")
    except _PushRejected:
        outcome = _failed(snapshot, "push_rejected", "profile publication was rejected")
    except _PushRaceExhausted:
        outcome = _failed(
            snapshot,
            "push_race_exhausted",
            "profile publication changed repeatedly",
        )
    except Exception:
        outcome = _failed(snapshot, "repository", "profile snapshot synchronization failed")

    resources: list[tuple[Callable[[Path], bool], Path]] = []
    if askpass is not None:
        resources.append((_unlink, askpass))
    if repository is not None:
        resources.append((_remove_tree, repository))
    cleanup_failed = _cleanup_resources(tuple(resources))
    if cleanup_failed:
        return _failed(
            snapshot,
            "cleanup_failed",
            "could not clean private profile publication resources",
        )
    return outcome


def _exact_tree_attempt(
    snapshot: ProfileSnapshot, repository: Path, environment: dict[str, str]
) -> _Attempt:
    declaration = snapshot.declaration
    _require_git(("init", "--quiet"), repository, environment)
    _require_git(
        ("remote", "add", "origin", "--", declaration.source),
        repository,
        environment,
    )
    observed = _git_ascii(
        ("config", "--get", "remote.origin.url"), repository, environment
    )
    if observed is None or not _same_remote_identity(declaration.source, observed):
        raise ValueError("remote identity mismatch")
    branch_ref = _validated_branch_ref(
        declaration.ref, repository, environment
    )
    _require_git(
        ("fetch", "--no-tags", "origin", "--", branch_ref),
        repository,
        environment,
    )
    remote_commit = _git_object_id(
        ("rev-parse", "--verify", "FETCH_HEAD^{commit}"), repository, environment
    )
    _require_git(("read-tree", "--empty"), repository, environment)
    _copy_snapshot(snapshot, repository)
    _require_git(("add", "-A", "--", "."), repository, environment)
    _validate_staged_paths(snapshot, repository, environment)
    tree = _git_object_id(("write-tree",), repository, environment)
    return _Attempt(remote_commit, tree)


def _profile_diff(
    repository: Path,
    environment: dict[str, str],
    auth: GitAuth,
    base_commit: str,
) -> ProfileDiff:
    raw = _git_bytes(
        (
            "diff",
            "--cached",
            "--name-status",
            "-z",
            "--no-renames",
            base_commit,
        ),
        repository,
        environment,
        max_output_bytes=_INDEX_OUTPUT_MAX_BYTES,
    )
    records = _nul_records(raw)
    if len(records) % 2:
        raise ValueError("invalid profile diff")
    changes: dict[bytes, list[PurePosixPath]] = {b"A": [], b"M": [], b"D": []}
    for index in range(0, len(records), 2):
        status_code = records[index]
        raw_path = records[index + 1]
        if status_code == b"T":
            status_code = b"M"
        if status_code not in changes:
            raise ValueError("invalid profile diff")
        path = _reported_path(raw_path, auth)
        changes[status_code].append(path)
    for paths in changes.values():
        paths.sort(key=lambda path: path.as_posix())
    return ProfileDiff(
        added=tuple(changes[b"A"]),
        modified=tuple(changes[b"M"]),
        deleted=tuple(changes[b"D"]),
    )


def _reported_path(raw: bytes, auth: GitAuth) -> PurePosixPath:
    try:
        text = raw.decode("ascii", "strict")
    except UnicodeError:
        raise ValueError("unsafe profile diff path") from None
    path = PurePosixPath(text)
    if (
        not text
        or path.is_absolute()
        or path.as_posix() != text
        or any(part in {"", ".", ".."} for part in path.parts)
        or any(ord(character) < 32 or ord(character) == 127 for character in text)
        or auth.redactor.redact(text) != text
    ):
        raise ValueError("unsafe profile diff path")
    return path


def _commit_and_push(
    snapshot: ProfileSnapshot,
    attempt: _Attempt,
    repository: Path,
    environment: dict[str, str],
) -> tuple[str, str]:
    declaration = snapshot.declaration
    _validated_branch_ref(declaration.ref, repository, environment)
    parent = attempt.remote_commit
    for publication_attempt in range(2):
        if publication_attempt:
            rebuilt_tree = _rebuild_snapshot_tree(
                snapshot, repository, environment
            )
            if rebuilt_tree != attempt.tree:
                raise ValueError("profile snapshot tree changed during retry")
        commit = _create_commit(
            snapshot, attempt.tree, parent, repository, environment
        )
        pushed = _push_commit(snapshot, commit, repository, environment)
        remote_commit, remote_tree = _fetch_remote(
            snapshot, repository, environment
        )
        if _publication_matches(
            commit,
            attempt.tree,
            remote_commit,
            remote_tree,
            pushed=pushed,
            repository=repository,
            environment=environment,
        ):
            return remote_commit, parent
        if not pushed and remote_commit == parent:
            raise _PushRejected
        if publication_attempt:
            raise _PushRaceExhausted
        parent = remote_commit
    raise _PushRaceExhausted


def _rebuild_snapshot_tree(
    snapshot: ProfileSnapshot,
    repository: Path,
    environment: dict[str, str],
) -> str:
    _require_git(("read-tree", "--empty"), repository, environment)
    _require_git(("add", "-A", "--", "."), repository, environment)
    _validate_staged_paths(snapshot, repository, environment)
    return _git_object_id(("write-tree",), repository, environment)


def _create_commit(
    snapshot: ProfileSnapshot,
    tree: str,
    parent: str,
    repository: Path,
    environment: dict[str, str],
) -> str:
    declaration = snapshot.declaration
    return _git_object_id(
        (
            "-c",
            "user.name=Hermes Bootstrap",
            "-c",
            "user.email=hermes-bootstrap@localhost",
            "commit-tree",
            tree,
            "-p",
            parent,
            "-m",
            f"chore: sync Hermes profile {declaration.name}",
        ),
        repository,
        environment,
    )


def _push_commit(
    snapshot: ProfileSnapshot,
    commit: str,
    repository: Path,
    environment: dict[str, str],
) -> bool:
    declaration = snapshot.declaration
    destination = f"refs/heads/{declaration.ref}"
    return _run_git_bytes(
        (
            "push",
            "--porcelain",
            "--",
            declaration.source,
            f"{commit}:{destination}",
        ),
        repository,
        environment,
        max_output_bytes=_COMMAND_OUTPUT_MAX_BYTES,
    ) is not None


def _validated_branch_ref(
    branch: str, repository: Path, environment: dict[str, str]
) -> str:
    if (
        not _valid_ref(branch)
        or branch == "HEAD"
        or branch.startswith("refs/")
    ):
        raise ValueError("invalid profile destination branch")
    observed = _git_ascii(
        ("check-ref-format", "--branch", branch), repository, environment
    )
    if observed != branch:
        raise ValueError("invalid profile destination branch")
    return f"refs/heads/{branch}"


def _publication_matches(
    commit: str,
    expected_tree: str,
    remote_commit: str,
    remote_tree: str,
    *,
    pushed: bool,
    repository: Path,
    environment: dict[str, str],
) -> bool:
    if remote_tree != expected_tree:
        return False
    if remote_commit == commit or not pushed:
        return True
    return _run_git_bytes(
        ("merge-base", "--is-ancestor", commit, remote_commit),
        repository,
        environment,
        max_output_bytes=_COMMAND_OUTPUT_MAX_BYTES,
    ) is not None


def _fetch_remote(
    snapshot: ProfileSnapshot,
    repository: Path,
    environment: dict[str, str],
) -> tuple[str, str]:
    declaration = snapshot.declaration
    branch_ref = _validated_branch_ref(
        declaration.ref, repository, environment
    )
    _require_git(
        ("fetch", "--no-tags", "origin", "--", branch_ref),
        repository,
        environment,
    )
    commit = _git_object_id(
        ("rev-parse", "--verify", "FETCH_HEAD^{commit}"), repository, environment
    )
    tree = _git_object_id(
        ("rev-parse", "--verify", "FETCH_HEAD^{tree}"), repository, environment
    )
    return commit, tree


def _copy_snapshot(snapshot: ProfileSnapshot, repository: Path) -> None:
    _write_file(repository / ".gitignore", snapshot.gitignore_bytes, 0o644)
    _write_file(repository / "distribution.yaml", snapshot.manifest_bytes, 0o644)
    for entry in snapshot.entries:
        source = snapshot.root.joinpath(*entry.path.parts)
        destination = repository.joinpath(*entry.path.parts)
        try:
            metadata = source.lstat()
        except OSError:
            raise ValueError("snapshot entry unavailable") from None
        if (
            not stat.S_ISREG(metadata.st_mode)
            or stat.S_ISLNK(metadata.st_mode)
            or stat.S_IMODE(metadata.st_mode) != entry.mode
            or metadata.st_size != entry.size
        ):
            raise ValueError("snapshot entry changed")
        content = source.read_bytes()
        if (
            len(content) != entry.size
            or hashlib.sha256(content).hexdigest() != entry.sha256
        ):
            raise ValueError("snapshot entry changed")
        _write_file(destination, content, entry.mode)


def _write_file(path: Path, content: bytes, mode: int) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    descriptor = os.open(
        path,
        os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC,
        mode,
    )
    try:
        with os.fdopen(descriptor, "wb", closefd=False) as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.fchmod(descriptor, mode)
    finally:
        os.close(descriptor)


def _validate_staged_paths(
    snapshot: ProfileSnapshot, repository: Path, environment: dict[str, str]
) -> None:
    raw = _git_bytes(
        ("ls-files", "--stage", "-z"),
        repository,
        environment,
        max_output_bytes=_INDEX_OUTPUT_MAX_BYTES,
    )
    expected = {
        b".gitignore": b"100644",
        b"distribution.yaml": b"100644",
        **{
            entry.path.as_posix().encode("ascii"): f"100{entry.mode:o}".encode(
                "ascii"
            )
            for entry in snapshot.entries
        },
    }
    observed: dict[bytes, bytes] = {}
    for record in _nul_records(raw):
        metadata, separator, path = record.partition(b"\t")
        fields = metadata.split(b" ")
        if (
            not separator
            or len(fields) != 3
            or fields[0] != expected.get(path)
            or _OBJECT_ID.fullmatch(fields[1]) is None
            or fields[2] != b"0"
            or not path
            or path in observed
        ):
            raise ValueError("unsafe staged profile entry")
        observed[path] = fields[0]
    if observed != expected:
        raise ValueError("staged profile paths do not match snapshot")


def _validate_snapshot_declaration(
    snapshot: ProfileSnapshot, auth: GitAuth, data_root: Path
) -> None:
    declaration = snapshot.declaration
    if (
        not isinstance(snapshot, ProfileSnapshot)
        or not _valid_auth(auth)
        or _remote_identity(declaration.source) is None
        or not _valid_ref(declaration.ref)
        or declaration.target != data_root / "profiles" / declaration.name
        or not data_root.is_absolute()
        or not _safe_directory(data_root)
        or not _safe_directory(snapshot.root)
    ):
        raise ValueError("invalid profile publication declaration")


def _git_bytes(
    arguments: tuple[str, ...],
    repository: Path,
    environment: dict[str, str],
    *,
    max_output_bytes: int = _COMMAND_OUTPUT_MAX_BYTES,
) -> bytes:
    output = _run_git_bytes(
        arguments, repository, environment, max_output_bytes=max_output_bytes
    )
    if output is None:
        raise ValueError("Git command failed")
    return output


def _require_git(
    arguments: tuple[str, ...], repository: Path, environment: dict[str, str]
) -> None:
    _git_bytes(arguments, repository, environment)


def _git_ascii(
    arguments: tuple[str, ...], repository: Path, environment: dict[str, str]
) -> str | None:
    try:
        return _git_bytes(arguments, repository, environment).decode("ascii", "strict").strip()
    except (UnicodeError, ValueError):
        return None


def _git_object_id(
    arguments: tuple[str, ...], repository: Path, environment: dict[str, str]
) -> str:
    raw = _git_bytes(arguments, repository, environment).strip()
    if _OBJECT_ID.fullmatch(raw) is None:
        raise ValueError("invalid Git object identity")
    return raw.decode("ascii").lower()


def _nul_records(raw: bytes) -> tuple[bytes, ...]:
    if not raw:
        return ()
    if not raw.endswith(b"\0"):
        raise ValueError("invalid NUL-delimited Git output")
    return tuple(raw[:-1].split(b"\0"))


def _failed(snapshot: ProfileSnapshot, category: str, message: str) -> ProfileSyncResult:
    return ProfileSyncResult(
        name=snapshot.declaration.name,
        status="failed",
        commit=None,
        snapshot=snapshot.digest,
        diff=ProfileDiff(),
        category=category,
        message=message,
    )


def _cleanup_resources(
    resources: tuple[tuple[Callable[[Path], bool], Path], ...]
) -> bool:
    failed = False
    for cleanup, path in resources:
        try:
            if not cleanup(path):
                failed = True
        except Exception as error:
            _scrub_exception_graph(error)
            failed = True
    return failed


def _scrub_exception_graph(error: BaseException) -> None:
    pending = [error]
    visited: set[int] = set()
    while pending:
        current = pending.pop()
        if id(current) in visited:
            continue
        visited.add(id(current))
        cause = current.__cause__
        context = current.__context__
        if cause is not None:
            pending.append(cause)
        if context is not None:
            pending.append(context)
        if isinstance(current, BaseExceptionGroup):
            pending.extend(current.exceptions)
        try:
            current.args = ()
        except Exception:
            pass
        try:
            current.__notes__ = []
        except Exception:
            pass
        current.__traceback__ = None
        current.__cause__ = None
        current.__context__ = None


def _safe_directory(path: Path) -> bool:
    try:
        metadata = path.lstat()
    except OSError:
        return False
    return stat.S_ISDIR(metadata.st_mode) and not stat.S_ISLNK(metadata.st_mode)


def _unlink(path: Path) -> bool:
    try:
        path.unlink()
    except OSError:
        return False
    return not path.exists()


def _remove_tree(path: Path) -> bool:
    try:
        metadata = path.lstat()
        if stat.S_ISDIR(metadata.st_mode) and not stat.S_ISLNK(metadata.st_mode):
            shutil.rmtree(path)
        else:
            path.unlink()
    except OSError:
        return False
    return not path.exists()
