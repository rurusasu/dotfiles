"""Locked synchronization and local migration for shared Hermes repositories."""

from __future__ import annotations

import errno
import fcntl
import os
import re
import shutil
import stat
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol

from .distributions import ChangeSet
from .errors import MigrationError, RepositoryError
from .git import (
    _create_askpass,
    _git_environment,
    _remote_identity,
    _run_git_bytes,
    _safe_unlink,
    _same_remote_identity,
    _valid_auth,
    _valid_ref,
)
from .github import GitAuth
from .models import BootstrapManifest, SharedRepository
from .payload import SecretRedactor


_OBJECT_ID = re.compile(r"[0-9a-f]{40}(?:[0-9a-f]{24})?\Z")
_REPOSITORY_NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9_.-]*\Z")
_STATUS_OUTPUT_MAX_BYTES = 4096
_FORBIDDEN_COMPONENT_MARKERS = ("auth", "token", "secret", "credential")
_FORBIDDEN_DIRECTORIES = frozenset({"memories", "sessions", "logs", "cache", "caches", "generated", "runtime"})
_RUNTIME_DATABASE_SUFFIXES = (".db", ".db-shm", ".db-wal")
_LOCAL_VALIDATION_AUTH = GitAuth("local-validation", SecretRedactor(("local-validation",)))


@dataclass(frozen=True)
class RemoteSyncResult:
    name: str
    commit: str
    pushed: bool
    working_tree: Path | None


class Transaction(Protocol):
    def snapshot(self, path: Path) -> None: ...

    def record_move(self, source: Path, target: Path) -> None: ...


@dataclass(frozen=True)
class _Failure:
    message: str


@dataclass(frozen=True)
class _MigrationFailure:
    canonical: Path | None = None
    legacy: Path | None = None


class _LockBusy(Exception):
    def __init__(self, path: Path) -> None:
        self.path = path


class _RepositoryLock:
    def __init__(self, path: Path) -> None:
        self._path = path
        self._descriptor: int | None = None

    def __enter__(self) -> None:
        _ensure_safe_directory(self._path.parent)
        if _lexists(self._path):
            mode = self._path.lstat().st_mode
            if stat.S_ISLNK(mode) or not stat.S_ISREG(mode):
                raise ValueError("lock is unsafe")
        flags = os.O_RDWR | os.O_CREAT | os.O_CLOEXEC
        if hasattr(os, "O_NOFOLLOW"):
            flags |= os.O_NOFOLLOW
        descriptor = os.open(self._path, flags, 0o600)
        try:
            mode = os.fstat(descriptor).st_mode
            if not stat.S_ISREG(mode):
                raise ValueError("lock is not regular")
            os.fchmod(descriptor, 0o600)
            try:
                fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except OSError as error:
                if error.errno in {errno.EACCES, errno.EAGAIN}:
                    raise _LockBusy(self._path) from None
                raise
            self._descriptor = descriptor
        except Exception:
            os.close(descriptor)
            raise

    def __exit__(self, _kind: object, _value: object, _traceback: object) -> None:
        if self._descriptor is None:
            return
        try:
            fcntl.flock(self._descriptor, fcntl.LOCK_UN)
        finally:
            os.close(self._descriptor)
            self._descriptor = None


def synchronize_remote(repo: SharedRepository, auth: GitAuth) -> RemoteSyncResult:
    """Synchronize one declared repository without entering the local transaction."""

    result = _synchronize_remote_boundary(repo, auth)
    if isinstance(result, _Failure):
        message = result.message
        del result
        del repo
        del auth
        raise RepositoryError(message)
    return result


def apply_shared_working_tree(repo: SharedRepository, result: RemoteSyncResult, tx: Transaction) -> ChangeSet:
    """Move an already synchronized checkout to its canonical path and link legacy users."""

    outcome = _apply_shared_working_tree_boundary(repo, result, tx)
    if isinstance(outcome, _MigrationFailure):
        if outcome.canonical is not None and outcome.legacy is not None:
            message = f"shared repository data exists at {outcome.canonical} and {outcome.legacy}"
            error_type: type[RepositoryError] | type[MigrationError] = MigrationError
        else:
            message = "could not migrate the shared repository working tree"
            error_type = MigrationError
        del outcome
        del repo
        del result
        del tx
        raise error_type(message)
    if isinstance(outcome, _Failure):
        message = outcome.message
        del outcome
        del repo
        del result
        del tx
        raise RepositoryError(message)
    return outcome


def synchronize_named_repository(
    name: str,
    manifest: BootstrapManifest,
    auth: GitAuth,
    *,
    require_canonical: bool = False,
) -> RemoteSyncResult:
    """Synchronize a declared repository, optionally requiring the runtime checkout."""

    selected = next((repo for repo in manifest.shared_repositories if repo.name == name), None)
    if selected is None:
        raise RepositoryError("unknown shared repository name")
    if require_canonical and not _looks_like_checkout(selected.target):
        raise RepositoryError("the canonical shared repository checkout is unavailable")
    return synchronize_remote(selected, auth)


def _synchronize_remote_boundary(repo: SharedRepository, auth: GitAuth) -> RemoteSyncResult | _Failure:
    stage: Path | None = None
    askpass: Path | None = None
    try:
        _validate_declaration(repo, auth)
        lock_path = _lock_path(repo)
        with _RepositoryLock(lock_path):
            working_tree = _selected_working_tree(repo)
            if working_tree is None:
                _ensure_safe_directory(repo.target.parent)
                stage = Path(tempfile.mkdtemp(prefix=".hermes-repository-", dir=repo.target.parent))
                os.chmod(stage, 0o700)
                working_tree = stage
            askpass = _create_askpass(working_tree.parent)
            environment = _git_environment(auth, askpass)
            if stage is not None:
                _initialize_checkout(repo, stage, environment)
            else:
                _verify_checkout_identity(repo, working_tree, environment)
            commit, pushed = _synchronize_checkout(repo, working_tree, environment)
            if stage is not None:
                stage = None
            return RemoteSyncResult(repo.name, commit, pushed, working_tree)
    except _LockBusy as error:
        return _Failure(str(error.path))
    except Exception:
        return _Failure("could not synchronize shared repository")
    finally:
        if askpass is not None:
            _safe_unlink(askpass)
        if stage is not None:
            _remove_tree(stage)


def _apply_shared_working_tree_boundary(
    repo: SharedRepository, result: RemoteSyncResult, tx: Transaction
) -> ChangeSet | _Failure | _MigrationFailure:
    try:
        _validate_result(repo, result)
        canonical_real = _real_data_state(repo.target, allow_legacy_link=False, repo=repo)
        legacy_real = False
        if repo.legacy_target is not None:
            legacy_real = _real_data_state(repo.legacy_target, allow_legacy_link=True, repo=repo)
        if canonical_real and legacy_real:
            return _MigrationFailure(repo.target, repo.legacy_target)

        working_tree = result.working_tree
        if working_tree is None:
            raise ValueError("missing synchronized checkout")
        _validate_working_tree(repo, repo.target if canonical_real else working_tree, result.commit)
        changed: list[Path] = []
        if not canonical_real:
            _ensure_parent_for_transaction(repo.target.parent, tx, changed)
            _snapshot(tx, repo.target)
            _snapshot(tx, working_tree)
            _require_same_filesystem(working_tree, repo.target.parent)
            tx.record_move(working_tree, repo.target)
            os.replace(working_tree, repo.target)
            changed.append(repo.target)
        _validate_working_tree(repo, repo.target, result.commit)
        if repo.legacy_target is not None:
            _create_legacy_link(repo, tx, changed)
        return ChangeSet(tuple(changed))
    except Exception:
        return _Failure("could not apply the shared repository working tree")


def _validate_declaration(repo: SharedRepository, auth: GitAuth) -> None:
    if (
        not isinstance(repo, SharedRepository)
        or _REPOSITORY_NAME.fullmatch(repo.name) is None
        or repo.mode not in {"read-only", "read-write"}
        or not _valid_auth(auth)
        or _remote_identity(repo.source) is None
        or not _valid_ref(repo.ref)
        or not repo.target.is_absolute()
        or repo.target.name != repo.name
        or repo.target.parent.name != "shared"
        or (repo.mode == "read-write" and not repo.sync_owner)
    ):
        raise ValueError("invalid repository declaration")
    if repo.legacy_target is not None and not repo.legacy_target.is_absolute():
        raise ValueError("invalid legacy target")


def _lock_path(repo: SharedRepository) -> Path:
    return repo.target.parent.parent / "locks" / "repositories" / f"{repo.name}.lock"


def _selected_working_tree(repo: SharedRepository) -> Path | None:
    canonical = _real_data_state(repo.target, allow_legacy_link=False, repo=repo)
    if canonical:
        return repo.target
    if repo.legacy_target is not None and _real_data_state(repo.legacy_target, allow_legacy_link=True, repo=repo):
        return repo.legacy_target
    return None


def _initialize_checkout(repo: SharedRepository, checkout: Path, environment: dict[str, str]) -> None:
    _require_git_success(("init", "--quiet"), checkout, environment)
    _require_git_success(("remote", "add", "origin", "--", repo.source), checkout, environment)
    _verify_checkout_identity(repo, checkout, environment)
    remote_commit = _fetch_declared_commit(repo, checkout, environment)
    _require_git_success(("checkout", "--detach", remote_commit), checkout, environment)
    if _head_commit(checkout, environment) != remote_commit:
        raise ValueError("checkout commit mismatch")


def _verify_checkout_identity(repo: SharedRepository, checkout: Path, environment: dict[str, str]) -> None:
    if not _looks_like_checkout(checkout):
        raise ValueError("not a checkout")
    remote = _git_ascii(("config", "--get", "remote.origin.url"), checkout, environment)
    if remote is None or not _same_remote_identity(repo.source, remote):
        raise ValueError("remote identity mismatch")


def _synchronize_checkout(repo: SharedRepository, checkout: Path, environment: dict[str, str]) -> tuple[str, bool]:
    if repo.mode == "read-only":
        if _git_bytes(("status", "--porcelain=v1", "-z", "--untracked-files=all"), checkout, environment) != b"":
            raise ValueError("read-only checkout is dirty")
        remote_commit = _fetch_declared_commit(repo, checkout, environment)
        head = _head_commit(checkout, environment)
        if not _is_ancestor(head, remote_commit, checkout, environment):
            raise ValueError("read-only checkout is not fast-forwardable")
        _require_git_success(("merge", "--ff-only", "FETCH_HEAD"), checkout, environment)
        if _head_commit(checkout, environment) != remote_commit:
            raise ValueError("read-only checkout did not reach declared commit")
        return remote_commit, False

    _reject_forbidden_status_paths(_git_bytes(("status", "--porcelain=v1", "-z", "--untracked-files=all"), checkout, environment))
    _require_git_success(("add", "-A", "--", "."), checkout, environment)
    staged = _git_bytes(("diff", "--cached", "--name-only", "-z"), checkout, environment)
    _reject_forbidden_name_list(staged)
    if staged:
        _require_git_success(
            (
                "-c",
                "user.name=Hermes Bootstrap",
                "-c",
                "user.email=hermes-bootstrap@localhost",
                "commit",
                "--no-gpg-sign",
                "-m",
                f"chore: sync Hermes {repo.name}",
            ),
            checkout,
            environment,
        )
    remote_commit = _fetch_declared_commit(repo, checkout, environment)
    if _git_bytes(("rebase", "FETCH_HEAD"), checkout, environment) is None:
        if _git_bytes(("rebase", "--abort"), checkout, environment) is None:
            raise ValueError("could not abort rebase")
        raise ValueError("rebase failed")
    head = _head_commit(checkout, environment)
    ahead = _git_ascii(("rev-list", "--count", "FETCH_HEAD..HEAD"), checkout, environment)
    if ahead is None or not ahead.isdecimal():
        raise ValueError("could not count local commits")
    pushed = int(ahead) > 0
    if pushed:
        _require_git_success(("push", "origin", f"HEAD:{repo.ref}"), checkout, environment)
    return head, pushed


def _fetch_declared_commit(repo: SharedRepository, checkout: Path, environment: dict[str, str]) -> str:
    _require_git_success(("fetch", "--no-tags", "origin", "--", repo.ref), checkout, environment)
    commit = _git_ascii(("rev-parse", "--verify", "FETCH_HEAD^{commit}"), checkout, environment)
    if commit is None or _OBJECT_ID.fullmatch(commit.lower()) is None:
        raise ValueError("declared ref is not a commit")
    return commit.lower()


def _head_commit(checkout: Path, environment: dict[str, str]) -> str:
    commit = _git_ascii(("rev-parse", "--verify", "HEAD^{commit}"), checkout, environment)
    if commit is None or _OBJECT_ID.fullmatch(commit.lower()) is None:
        raise ValueError("head is not a commit")
    return commit.lower()


def _is_ancestor(ancestor: str, descendant: str, checkout: Path, environment: dict[str, str]) -> bool:
    return _git_bytes(("merge-base", "--is-ancestor", ancestor, descendant), checkout, environment) is not None


def _git_bytes(arguments: tuple[str, ...], checkout: Path, environment: dict[str, str]) -> bytes:
    output = _run_git_bytes(arguments, checkout, environment, max_output_bytes=_STATUS_OUTPUT_MAX_BYTES)
    if output is None:
        raise ValueError("git command failed")
    return output


def _git_ascii(arguments: tuple[str, ...], checkout: Path, environment: dict[str, str]) -> str | None:
    try:
        return _git_bytes(arguments, checkout, environment).decode("ascii", "strict").strip()
    except (UnicodeError, ValueError):
        return None


def _require_git_success(arguments: tuple[str, ...], checkout: Path, environment: dict[str, str]) -> None:
    _git_bytes(arguments, checkout, environment)


def _reject_forbidden_status_paths(status: bytes) -> None:
    if not status:
        return
    records = status.split(b"\0")
    if records.pop() != b"":
        raise ValueError("status is not NUL delimited")
    index = 0
    while index < len(records):
        record = records[index]
        index += 1
        if len(record) < 4 or record[2:3] != b" ":
            raise ValueError("invalid status record")
        state = record[:2]
        _reject_forbidden_path(record[3:])
        if b"R" in state or b"C" in state:
            if index >= len(records):
                raise ValueError("missing rename status path")
            _reject_forbidden_path(records[index])
            index += 1


def _reject_forbidden_name_list(names: bytes) -> None:
    if not names:
        return
    records = names.split(b"\0")
    if records.pop() != b"":
        raise ValueError("name list is not NUL delimited")
    for name in records:
        _reject_forbidden_path(name)


def _reject_forbidden_path(raw: bytes) -> None:
    value = os.fsdecode(raw)
    if not value or value.startswith(("/", "\\")) or "\\" in value:
        raise ValueError("unsafe path")
    components = value.split("/")
    if any(not component or component in {".", ".."} for component in components):
        raise ValueError("unsafe path")
    for component in components:
        folded = component.casefold()
        if (
            folded in {".git", ".env"}
            or folded in _FORBIDDEN_DIRECTORIES
            or any(marker in folded for marker in _FORBIDDEN_COMPONENT_MARKERS)
            or folded.endswith(_RUNTIME_DATABASE_SUFFIXES)
        ):
            raise ValueError("forbidden repository path")


def _validate_result(repo: SharedRepository, result: RemoteSyncResult) -> None:
    if (
        not isinstance(result, RemoteSyncResult)
        or result.name != repo.name
        or type(result.pushed) is not bool
        or not isinstance(result.working_tree, Path)
        or _OBJECT_ID.fullmatch(result.commit) is None
        or result.commit != result.commit.lower()
    ):
        raise ValueError("invalid synchronization result")
    allowed = {repo.target}
    if repo.legacy_target is not None:
        allowed.add(repo.legacy_target)
    if result.working_tree not in allowed:
        if result.working_tree.parent != repo.target.parent or not result.working_tree.name.startswith(".hermes-repository-"):
            raise ValueError("synchronization result path is invalid")


def _validate_working_tree(repo: SharedRepository, checkout: Path, commit: str) -> None:
    if not _looks_like_checkout(checkout):
        raise ValueError("working tree is not safe")
    askpass: Path | None = None
    try:
        askpass = _create_askpass(checkout.parent)
        environment = _git_environment(_LOCAL_VALIDATION_AUTH, askpass)
        _verify_checkout_identity(repo, checkout, environment)
        if _head_commit(checkout, environment) != commit:
            raise ValueError("working tree commit mismatch")
    finally:
        if askpass is not None:
            _safe_unlink(askpass)


def _real_data_state(path: Path, *, allow_legacy_link: bool, repo: SharedRepository) -> bool:
    if not _lexists(path):
        return False
    mode = path.lstat().st_mode
    if stat.S_ISLNK(mode):
        if allow_legacy_link and _is_correct_legacy_link(repo):
            return False
        raise ValueError("unexpected symlink")
    if not stat.S_ISDIR(mode):
        raise ValueError("shared repository target is not a directory")
    with os.scandir(path) as entries:
        return next(entries, None) is not None


def _create_legacy_link(repo: SharedRepository, tx: Transaction, changed: list[Path]) -> None:
    legacy = repo.legacy_target
    if legacy is None or _is_correct_legacy_link(repo):
        return
    if _lexists(legacy):
        mode = legacy.lstat().st_mode
        if stat.S_ISLNK(mode) or not stat.S_ISDIR(mode):
            raise ValueError("unexpected legacy target")
        with os.scandir(legacy) as entries:
            if next(entries, None) is not None:
                raise ValueError("legacy target contains data")
    _ensure_parent_for_transaction(legacy.parent, tx, changed)
    _snapshot(tx, legacy)
    if _lexists(legacy):
        legacy.rmdir()
    os.symlink(os.path.relpath(repo.target, legacy.parent), legacy)
    changed.append(legacy)


def _is_correct_legacy_link(repo: SharedRepository) -> bool:
    legacy = repo.legacy_target
    if legacy is None or not _lexists(legacy):
        return False
    try:
        return stat.S_ISLNK(legacy.lstat().st_mode) and os.readlink(legacy) == os.path.relpath(repo.target, legacy.parent)
    except OSError:
        return False


def _ensure_parent_for_transaction(path: Path, tx: Transaction, changed: list[Path]) -> None:
    missing: list[Path] = []
    current = path
    while not _lexists(current):
        missing.append(current)
        current = current.parent
    if not _safe_directory(current):
        raise ValueError("unsafe parent")
    for directory in reversed(missing):
        _snapshot(tx, directory)
        directory.mkdir(mode=0o700)
        changed.append(directory)


def _require_same_filesystem(source: Path, destination_parent: Path) -> None:
    if source.stat().st_dev != destination_parent.stat().st_dev:
        raise ValueError("working tree is on another filesystem")


def _looks_like_checkout(path: Path) -> bool:
    if not _safe_directory(path):
        return False
    metadata = path / ".git"
    return _safe_directory(metadata)


def _ensure_safe_directory(path: Path) -> None:
    missing: list[Path] = []
    current = path
    while not _lexists(current):
        missing.append(current)
        current = current.parent
    if not _safe_directory(current):
        raise ValueError("unsafe directory")
    for directory in reversed(missing):
        directory.mkdir(mode=0o700)


def _safe_directory(path: Path) -> bool:
    try:
        mode = path.lstat().st_mode
    except OSError:
        return False
    return stat.S_ISDIR(mode) and not stat.S_ISLNK(mode)


def _lexists(path: Path) -> bool:
    try:
        path.lstat()
    except OSError:
        return False
    return True


def _snapshot(tx: Transaction, path: Path) -> None:
    tx.snapshot(path)


def _remove_tree(path: Path) -> None:
    try:
        if path.is_dir() and not path.is_symlink():
            shutil.rmtree(path)
        else:
            path.unlink(missing_ok=True)
    except OSError:
        pass
