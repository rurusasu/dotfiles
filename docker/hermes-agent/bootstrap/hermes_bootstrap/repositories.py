"""Locked synchronization and local migration for shared Hermes repositories."""

from __future__ import annotations

import ctypes
import errno
import fcntl
import os
import re
import shutil
import stat
import tempfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Protocol

from .distributions import ChangeSet
from .errors import MigrationError, RepositoryError
from .filesystem import (
    PrivateDirectory,
    create_private_directory,
    open_absolute_directory,
    verify_absolute_directory,
)
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
from .models import BootstrapManifest, SharedRepository
from .payload import SecretRedactor
_OBJECT_ID = re.compile(r"[0-9a-f]{40}(?:[0-9a-f]{24})?\Z")
_REPOSITORY_NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9_.-]*\Z")
_COMMAND_OUTPUT_MAX_BYTES = 64 * 1024
_STATUS_OUTPUT_MAX_BYTES = 8 * 1024 * 1024
_FORBIDDEN_CREDENTIAL_STEMS = frozenset(
    {"auth", "token", "tokens", "secret", "secrets", "credential", "credentials"}
)
_ALLOWED_ENV_TEMPLATES = frozenset({".env.example"})
_FORBIDDEN_DIRECTORIES = frozenset({"memories", "sessions", "logs", "cache", "caches", "generated", "runtime"})
_RUNTIME_DATABASE_SUFFIXES = (".db", ".db-shm", ".db-wal")
_ALLOWED_BLOB_MODES = frozenset({b"100644", b"100755"})
_RENAME_NOREPLACE = 1
_FORBIDDEN_GIT_METADATA = (
    Path("commondir"),
    Path("info/grafts"),
    Path("objects/info/alternates"),
    Path("objects/info/http-alternates"),
)


def _load_renameat2() -> Any | None:
    try:
        libc = ctypes.CDLL(None, use_errno=True)
        function = libc.renameat2
        function.argtypes = (
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_uint,
        )
        function.restype = ctypes.c_int
        return function
    except (AttributeError, OSError, TypeError):
        return None


_renameat2 = _load_renameat2()


def _rename_noreplace(source_parent: int, source: str, target_parent: int, target: str) -> None:
    if _renameat2 is None:
        raise OSError(errno.ENOSYS, "atomic no-replace rename is unavailable")
    ctypes.set_errno(0)
    result = _renameat2(
        source_parent,
        os.fsencode(source),
        target_parent,
        os.fsencode(target),
        _RENAME_NOREPLACE,
    )
    if result == 0:
        return
    error = ctypes.get_errno()
    if error == errno.EEXIST:
        raise FileExistsError(error, "atomic no-replace destination exists")
    if error == errno.ENOENT:
        raise FileNotFoundError(error, "atomic no-replace source is absent")
    raise OSError(error, "atomic no-replace rename failed")
_EXECUTABLE_LOCAL_CONFIG = frozenset(
    {
        "core.alternaterefscommand",
        "core.askpass",
        "core.attributesfile",
        "core.editor",
        "core.fsmonitor",
        "core.gitproxy",
        "core.hookspath",
        "core.sshcommand",
        "core.worktree",
        "credential.helper",
        "diff.external",
        "gpg.program",
        "gpg.ssh.defaultkeycommand",
        "gc.recentobjectshook",
        "interactive.difffilter",
        "extensions.worktreeconfig",
        "sequence.editor",
        "uploadpack.packobjectshook",
    }
)
_LOCAL_VALIDATION_AUTH = GitAuth("local-validation", SecretRedactor(("local-validation",)))


@dataclass(frozen=True)
class RemoteSyncResult:
    name: str
    commit: str
    pushed: bool
    working_tree: Path | None
    private_directory: PrivateDirectory | None = field(
        default=None,
        compare=False,
        repr=False,
    )


class Transaction(Protocol):
    def snapshot(self, path: Path) -> None: ...


@dataclass(frozen=True)
class _Failure:
    message: str


@dataclass(frozen=True)
class _MigrationFailure:
    canonical: Path | None = None
    legacy: Path | None = None


@dataclass(frozen=True)
class _IndexBackup:
    index: Path
    backup: Path


@dataclass(frozen=True)
class _PathIdentity:
    device: int
    inode: int
    file_type: int


class _LockBusy(Exception):
    def __init__(self, path: Path) -> None:
        self.path = path


class _RepositoryLock:
    def __init__(self, path: Path, data_root: Path) -> None:
        self._path = path
        self._data_root = data_root
        self._descriptor: int | None = None
        self._parent_descriptor: int | None = None
        self._root_descriptor: int | None = None
        self._identity: tuple[int, int] | None = None

    def __enter__(self) -> _RepositoryLock:
        _ensure_safe_directory(self._data_root)
        root_descriptor = open_absolute_directory(self._data_root)
        parent_descriptor: int | None = None
        descriptor: int | None = None
        flags = os.O_RDWR | os.O_CREAT | os.O_CLOEXEC
        if hasattr(os, "O_NOFOLLOW"):
            flags |= os.O_NOFOLLOW
        try:
            verify_absolute_directory(self._data_root, root_descriptor)
            try:
                fcntl.flock(root_descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except OSError as error:
                if error.errno in {errno.EACCES, errno.EAGAIN}:
                    raise _LockBusy(self._path) from None
                raise
            _ensure_safe_managed_directory(self._path.parent, self._data_root)
            parent_descriptor = open_absolute_directory(self._path.parent)
            verify_absolute_directory(self._path.parent, parent_descriptor)
            try:
                fcntl.flock(parent_descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except OSError as error:
                if error.errno in {errno.EACCES, errno.EAGAIN}:
                    raise _LockBusy(self._path) from None
                raise
            descriptor = os.open(self._path.name, flags, 0o600, dir_fd=parent_descriptor)
            metadata = os.fstat(descriptor)
            if not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1:
                raise ValueError("lock is unsafe")
            os.fchmod(descriptor, 0o600)
            try:
                fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except OSError as error:
                if error.errno in {errno.EACCES, errno.EAGAIN}:
                    raise _LockBusy(self._path) from None
                raise
            self._descriptor = descriptor
            self._parent_descriptor = parent_descriptor
            self._root_descriptor = root_descriptor
            self._identity = (metadata.st_dev, metadata.st_ino)
            self.require_held()
            return self
        except Exception:
            self._descriptor = None
            self._parent_descriptor = None
            self._root_descriptor = None
            self._identity = None
            if descriptor is not None:
                os.close(descriptor)
            if parent_descriptor is not None:
                os.close(parent_descriptor)
            os.close(root_descriptor)
            raise

    def require_held(self) -> None:
        if (
            self._descriptor is None
            or self._parent_descriptor is None
            or self._root_descriptor is None
            or self._identity is None
        ):
            raise ValueError("repository lock is not held")
        try:
            verify_absolute_directory(self._data_root, self._root_descriptor)
            verify_absolute_directory(self._path.parent, self._parent_descriptor)
            opened = os.fstat(self._descriptor)
            current = os.stat(
                self._path.name,
                dir_fd=self._parent_descriptor,
                follow_symlinks=False,
            )
        except OSError:
            raise ValueError("repository lock path changed") from None
        if (
            not stat.S_ISREG(opened.st_mode)
            or not stat.S_ISREG(current.st_mode)
            or opened.st_nlink != 1
            or current.st_nlink != 1
            or (opened.st_dev, opened.st_ino) != self._identity
            or (current.st_dev, current.st_ino) != self._identity
        ):
            raise ValueError("repository lock path changed")

    def __exit__(self, kind: object, _value: object, _traceback: object) -> None:
        integrity_error = False
        try:
            self.require_held()
        except ValueError:
            integrity_error = True
        if self._descriptor is not None:
            try:
                fcntl.flock(self._descriptor, fcntl.LOCK_UN)
            finally:
                os.close(self._descriptor)
                self._descriptor = None
        if self._parent_descriptor is not None:
            try:
                fcntl.flock(self._parent_descriptor, fcntl.LOCK_UN)
            finally:
                os.close(self._parent_descriptor)
                self._parent_descriptor = None
        if self._root_descriptor is not None:
            try:
                fcntl.flock(self._root_descriptor, fcntl.LOCK_UN)
            finally:
                os.close(self._root_descriptor)
                self._root_descriptor = None
        self._identity = None
        if integrity_error and kind is None:
            raise ValueError("repository lock path changed")


def synchronize_remote(repo: SharedRepository, auth: GitAuth) -> RemoteSyncResult:
    """Synchronize one declared repository without entering the local transaction."""

    result = _synchronize_remote_boundary(repo, auth)
    if isinstance(result, _MigrationFailure):
        message = f"shared repository data exists at {result.canonical} and {result.legacy}"
        del result
        del repo
        del auth
        raise MigrationError(message)
    if isinstance(result, _Failure):
        message = result.message
        del result
        del repo
        del auth
        raise RepositoryError(message)
    return result


def apply_shared_working_tree(repo: SharedRepository, result: RemoteSyncResult, tx: Transaction) -> ChangeSet:
    """Move a synchronized checkout to its canonical path and remove the legacy target."""

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


def _synchronize_remote_boundary(
    repo: SharedRepository, auth: GitAuth
) -> RemoteSyncResult | _Failure | _MigrationFailure:
    stage: PrivateDirectory | None = None
    askpass: Path | None = None
    outcome: RemoteSyncResult | _Failure
    try:
        _validate_declaration(repo, auth)
        data_root = _repository_data_root(repo)
        _require_safe_repository_parents(repo)
        lock_path = _lock_path(repo)
        with _RepositoryLock(lock_path, data_root) as repository_lock:
            repository_lock.require_held()
            working_tree = _selected_working_tree(repo)
            if isinstance(working_tree, _MigrationFailure):
                return working_tree
            if working_tree is None:
                _ensure_safe_managed_directory(repo.target.parent, data_root)
                stage = create_private_directory(
                    repo.target.parent,
                    prefix=".hermes-repository-",
                )
                working_tree = stage.path
            askpass = _create_askpass(working_tree.parent)
            environment = _git_environment(auth, askpass)
            local_environment = _local_git_environment(environment)
            if stage is not None:
                repository_lock.require_held()
                _initialize_checkout(repo, stage.path, environment)
            else:
                _verify_checkout_identity(repo, working_tree, local_environment)
            repository_lock.require_held()
            commit, pushed = _synchronize_checkout(repo, working_tree, environment)
            repository_lock.require_held()
            outcome = RemoteSyncResult(
                repo.name,
                commit,
                pushed,
                working_tree,
                stage,
            )
    except _LockBusy as error:
        outcome = _Failure(str(error.path))
    except Exception:
        outcome = _Failure("could not synchronize shared repository")

    cleanup_failed = askpass is not None and not _unlink_path(askpass)
    if stage is not None and (isinstance(outcome, _Failure) or cleanup_failed):
        cleanup_failed = not stage.cleanup() or cleanup_failed
    if cleanup_failed:
        return _Failure("could not clean private repository resources")
    return outcome


def _apply_shared_working_tree_boundary(
    repo: SharedRepository, result: RemoteSyncResult, tx: Transaction
) -> ChangeSet | _Failure | _MigrationFailure:
    try:
        data_root = _repository_data_root(repo)
        with _RepositoryLock(_lock_path(repo), data_root) as repository_lock:
            repository_lock.require_held()
            return _apply_shared_working_tree_locked(repo, result, tx)
    except _LockBusy as error:
        return _Failure(str(error.path))
    except Exception:
        return _Failure("could not apply the shared repository working tree")


def _apply_shared_working_tree_locked(
    repo: SharedRepository, result: RemoteSyncResult, tx: Transaction
) -> ChangeSet | _Failure | _MigrationFailure:
    publication_copy: PrivateDirectory | None = None
    try:
        _validate_result(repo, result)
        _require_safe_repository_parents(repo)
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
        migrated_legacy = False
        if not canonical_real:
            _ensure_parent_for_transaction(repo.target.parent, tx, changed)
            _snapshot(tx, repo.target)
            migrated_legacy = repo.legacy_target is not None and working_tree == repo.legacy_target
            publication_source = working_tree
            if migrated_legacy:
                publication_copy = _copy_working_tree_for_publication(repo, working_tree, result.commit)
                publication_source = publication_copy.path
            _require_same_filesystem(publication_source, repo.target.parent)
            _move_verified_working_tree(repo, publication_source, result.commit)
            if publication_copy is not None:
                publication_copy.release()
                if not publication_copy.is_released:
                    raise ValueError("could not release private repository copy")
                publication_copy = None
            elif result.private_directory is not None:
                result.private_directory.release()
                if not result.private_directory.is_released:
                    raise ValueError("could not release private repository stage")
            changed.append(repo.target)
        _validate_working_tree(repo, repo.target, result.commit)
        if repo.legacy_target is not None:
            _remove_legacy_target(repo, tx, changed, allow_populated=migrated_legacy)
        return ChangeSet(tuple(changed))
    except Exception:
        if publication_copy is not None and not publication_copy.cleanup():
            return _Failure("could not clean private repository resources")
        return _Failure("could not apply the shared repository working tree")


def _validate_declaration(repo: SharedRepository, auth: GitAuth) -> None:
    data_root = repo.target.parent.parent if isinstance(repo, SharedRepository) else None
    legacy_within_root = True
    if isinstance(repo, SharedRepository) and repo.legacy_target is not None:
        try:
            legacy_relative = repo.legacy_target.relative_to(data_root)
            legacy_within_root = bool(legacy_relative.parts) and ".." not in legacy_relative.parts
        except (TypeError, ValueError):
            legacy_within_root = False
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
        or repo.target != data_root / "shared" / repo.name
        or not legacy_within_root
        or (repo.mode == "read-write" and not repo.sync_owner)
    ):
        raise ValueError("invalid repository declaration")
    if repo.legacy_target is not None and not repo.legacy_target.is_absolute():
        raise ValueError("invalid legacy target")


def _lock_path(repo: SharedRepository) -> Path:
    return repo.target.parent.parent / "locks" / "repositories" / f"{repo.name}.lock"


def _selected_working_tree(repo: SharedRepository) -> Path | _MigrationFailure | None:
    canonical = _real_data_state(repo.target, allow_legacy_link=False, repo=repo)
    legacy = False
    if repo.legacy_target is not None:
        legacy = _real_data_state(repo.legacy_target, allow_legacy_link=True, repo=repo)
    if canonical and legacy:
        return _MigrationFailure(repo.target, repo.legacy_target)
    if canonical:
        return repo.target
    if legacy:
        return repo.legacy_target
    return None


def _initialize_checkout(repo: SharedRepository, checkout: Path, environment: dict[str, str]) -> None:
    _require_safe_checkout_location(repo, checkout)
    _require_git_success(("init", "--quiet"), checkout, environment)
    _require_git_success(("remote", "add", "origin", "--", repo.source), checkout, environment)
    _verify_checkout_identity(repo, checkout, environment)
    remote_commit = _fetch_declared_commit(repo, checkout, environment)
    _validate_commit_tree(checkout, _local_git_environment(environment), remote_commit)
    _require_safe_checkout_location(repo, checkout)
    _require_git_success(("checkout", "--detach", remote_commit), checkout, environment)
    if _head_commit(checkout, environment) != remote_commit:
        raise ValueError("checkout commit mismatch")


def _verify_checkout_identity(repo: SharedRepository, checkout: Path, environment: dict[str, str]) -> None:
    if not _looks_like_checkout(checkout):
        raise ValueError("not a checkout")
    _require_safe_checkout_location(repo, checkout)
    _reject_unsafe_git_metadata(checkout)
    _verify_git_metadata_location(checkout, environment)
    _reject_redirecting_local_config(checkout, environment)
    _reject_replace_refs(checkout, environment)
    _verify_effective_worktree(checkout, environment)
    remotes = _nul_records(
        _git_bytes(
            ("config", "--local", "--no-includes", "--null", "--get-all", "remote.origin.url"),
            checkout,
            environment,
        )
    )
    if len(remotes) != 1 or not _same_remote_identity(repo.source, os.fsdecode(remotes[0])):
        raise ValueError("remote identity mismatch")


def _synchronize_checkout(repo: SharedRepository, checkout: Path, environment: dict[str, str]) -> tuple[str, bool]:
    local_environment = _local_git_environment(environment)
    if repo.mode == "read-only":
        _validate_index(checkout, local_environment)
        _reject_external_hardlinks(checkout)
        if _git_bytes(
            ("status", "--porcelain=v1", "-z", "--untracked-files=all"),
            checkout,
            local_environment,
            max_output_bytes=_STATUS_OUTPUT_MAX_BYTES,
        ) != b"":
            raise ValueError("read-only checkout is dirty")
        remote_commit = _fetch_declared_commit(repo, checkout, environment)
        _validate_commit_tree(checkout, local_environment, remote_commit)
        head = _head_commit(checkout, local_environment)
        if not _is_ancestor(head, remote_commit, checkout, local_environment):
            raise ValueError("read-only checkout is not fast-forwardable")
        _require_safe_checkout_location(repo, checkout)
        _require_git_success(("merge", "--ff-only", "FETCH_HEAD"), checkout, local_environment)
        _validate_index(checkout, local_environment)
        _reject_external_hardlinks(checkout)
        if _head_commit(checkout, local_environment) != remote_commit:
            raise ValueError("read-only checkout did not reach declared commit")
        return remote_commit, False

    status_output = _git_bytes(
        ("status", "--porcelain=v1", "-z", "--untracked-files=all"),
        checkout,
        local_environment,
        max_output_bytes=_STATUS_OUTPUT_MAX_BYTES,
    )
    _reject_forbidden_status_paths(status_output)
    _validate_index(checkout, local_environment)
    _reject_external_hardlinks(checkout)
    remote_commit = _fetch_declared_commit(repo, checkout, environment)
    _validate_commit_tree(checkout, local_environment, remote_commit)
    _reject_preexisting_unpushed_commits(checkout, local_environment)
    staged = b""
    if status_output:
        backup = _backup_index(checkout)
        try:
            _require_safe_checkout_location(repo, checkout)
            _require_git_success(("add", "-A", "--", "."), checkout, local_environment)
            _validate_index(checkout, local_environment)
            staged = _git_bytes(
                ("diff", "--cached", "--name-only", "-z"),
                checkout,
                local_environment,
                max_output_bytes=_STATUS_OUTPUT_MAX_BYTES,
            )
            _reject_forbidden_name_list(staged)
            _reject_external_hardlinks(checkout)
        except Exception:
            _restore_index(backup)
            raise
        _discard_index_backup(backup)
    created_commit = False
    if staged:
        _require_safe_checkout_location(repo, checkout)
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
            local_environment,
        )
        created_commit = True
    publication_confirmed = False
    try:
        if _fetch_head_commit(checkout, local_environment) != remote_commit:
            raise ValueError("fetched commit changed unexpectedly")
        _validate_index(checkout, local_environment)
        _validate_unpushed_commits(checkout, local_environment)
        _require_safe_checkout_location(repo, checkout)
        if _try_git_bytes(("rebase", "FETCH_HEAD"), checkout, local_environment) is None:
            _require_safe_checkout_location(repo, checkout)
            if _try_git_bytes(("rebase", "--abort"), checkout, local_environment) is None:
                raise ValueError("could not abort rebase")
            raise ValueError("rebase failed")
        _validate_index(checkout, local_environment)
        _reject_external_hardlinks(checkout)
        head = _head_commit(checkout, local_environment)
        ahead = _git_ascii(("rev-list", "--count", "FETCH_HEAD..HEAD"), checkout, local_environment)
        if ahead is None or not ahead.isdecimal():
            raise ValueError("could not count local commits")
        pushed = int(ahead) > 0
        if pushed:
            _require_safe_checkout_location(repo, checkout)
            if _try_git_bytes(
                ("push", "--", repo.source, f"HEAD:{repo.ref}"), checkout, environment
            ) is None:
                confirmed = None
                try:
                    confirmed = _fetch_declared_commit(repo, checkout, environment)
                except ValueError:
                    pass
                if confirmed is None:
                    raise ValueError("push failed")
                if confirmed == head:
                    publication_confirmed = True
                elif _is_ancestor(head, confirmed, checkout, local_environment):
                    publication_confirmed = True
                    _validate_commit_tree(checkout, local_environment, confirmed)
                    _require_safe_checkout_location(repo, checkout)
                    _require_git_success(
                        ("merge", "--ff-only", "FETCH_HEAD"), checkout, local_environment
                    )
                    _validate_index(checkout, local_environment)
                    _reject_external_hardlinks(checkout)
                    head = confirmed
                else:
                    raise ValueError("push failed")
            else:
                publication_confirmed = True
        return head, pushed
    except Exception:
        if created_commit and not publication_confirmed:
            try:
                _require_safe_checkout_location(repo, checkout)
            except ValueError:
                pass
            else:
                _try_git_bytes(("reset", "--mixed", remote_commit), checkout, local_environment)
        raise


def _fetch_declared_commit(repo: SharedRepository, checkout: Path, environment: dict[str, str]) -> str:
    _require_safe_checkout_location(repo, checkout)
    _require_git_success(("fetch", "--no-tags", repo.source, "--", repo.ref), checkout, environment)
    return _fetch_head_commit(checkout, environment)


def _fetch_head_commit(checkout: Path, environment: dict[str, str]) -> str:
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


def _git_bytes(
    arguments: tuple[str, ...],
    checkout: Path,
    environment: dict[str, str],
    *,
    max_output_bytes: int = _COMMAND_OUTPUT_MAX_BYTES,
) -> bytes:
    output = _try_git_bytes(arguments, checkout, environment, max_output_bytes=max_output_bytes)
    if output is None:
        raise ValueError("git command failed")
    return output


def _try_git_bytes(
    arguments: tuple[str, ...],
    checkout: Path,
    environment: dict[str, str],
    *,
    max_output_bytes: int = _COMMAND_OUTPUT_MAX_BYTES,
) -> bytes | None:
    return _run_git_bytes(arguments, checkout, environment, max_output_bytes=max_output_bytes)


def _git_ascii(arguments: tuple[str, ...], checkout: Path, environment: dict[str, str]) -> str | None:
    try:
        return _git_bytes(arguments, checkout, environment).decode("ascii", "strict").strip()
    except (UnicodeError, ValueError):
        return None


def _require_git_success(arguments: tuple[str, ...], checkout: Path, environment: dict[str, str]) -> None:
    _git_bytes(arguments, checkout, environment)


def _local_git_environment(environment: dict[str, str]) -> dict[str, str]:
    local_environment = environment.copy()
    local_environment.pop("HERMES_BOOTSTRAP_GITHUB_TOKEN", None)
    return local_environment


def _verify_effective_worktree(checkout: Path, environment: dict[str, str]) -> None:
    effective = _git_path(
        ("rev-parse", "--path-format=absolute", "--show-toplevel"), checkout, environment
    )
    try:
        if not effective.samefile(checkout):
            raise ValueError("Git worktree does not match checkout")
    except OSError:
        raise ValueError("could not verify Git worktree") from None


def _verify_git_metadata_location(checkout: Path, environment: dict[str, str]) -> None:
    expected = checkout / ".git"
    git_directory = _git_path(("rev-parse", "--absolute-git-dir"), checkout, environment)
    common_directory = _git_path(
        ("rev-parse", "--path-format=absolute", "--git-common-dir"), checkout, environment
    )
    try:
        if not git_directory.samefile(expected) or not common_directory.samefile(expected):
            raise ValueError("Git metadata is outside the checkout")
    except OSError:
        raise ValueError("could not verify Git metadata") from None


def _git_path(
    arguments: tuple[str, ...], checkout: Path, environment: dict[str, str]
) -> Path:
    raw = _git_bytes(arguments, checkout, environment)
    if raw.endswith(b"\n"):
        raw = raw[:-1]
    if not raw or any(character in raw for character in (b"\x00", b"\r", b"\n")):
        raise ValueError("Git returned an invalid path")
    return Path(os.fsdecode(raw))


def _reject_unsafe_git_metadata(checkout: Path) -> None:
    metadata_root = checkout / ".git"
    if any(_lexists(metadata_root / relative) for relative in _FORBIDDEN_GIT_METADATA):
        raise ValueError("external Git metadata is forbidden")
    _reject_external_hardlinks_in_tree(
        metadata_root,
        skip_top_level_git=False,
        reject_nonregular=True,
    )


def _reject_redirecting_local_config(checkout: Path, environment: dict[str, str]) -> None:
    names = _nul_records(
        _git_bytes(
            ("config", "--local", "--no-includes", "--null", "--name-only", "--list"),
            checkout,
            environment,
            max_output_bytes=_STATUS_OUTPUT_MAX_BYTES,
        )
    )
    for raw_name in names:
        name = os.fsdecode(raw_name).casefold()
        if (
            name == "remote.origin.pushurl"
            or name == "include.path"
            or (name.startswith("includeif.") and name.endswith(".path"))
            or (name.startswith("url.") and name.endswith((".insteadof", ".pushinsteadof")))
            or _is_executable_local_config(name)
        ):
            raise ValueError("unsafe local Git config is forbidden")


def _reject_replace_refs(checkout: Path, environment: dict[str, str]) -> None:
    if _git_bytes(
        ("for-each-ref", "--format=%(refname)", "refs/replace"),
        checkout,
        environment,
        max_output_bytes=_STATUS_OUTPUT_MAX_BYTES,
    ):
        raise ValueError("Git replace refs are forbidden")


def _is_executable_local_config(name: str) -> bool:
    return (
        name in _EXECUTABLE_LOCAL_CONFIG
        or (name.startswith("alias.") and name.endswith(".command"))
        or (name.startswith("browser.") and name.endswith(".cmd"))
        or name.startswith("http.")
        or (name.startswith("credential.") and name.endswith(".helper"))
        or (name.startswith("diff.") and name.endswith((".command", ".textconv")))
        or (name.startswith("difftool.") and name.endswith(".cmd"))
        or (name.startswith("filter.") and name.endswith((".clean", ".smudge", ".process")))
        or (name.startswith("gpg.") and name.endswith(".program"))
        or (name.startswith("guitool.") and name.endswith(".cmd"))
        or (name.startswith("hook.") and name.endswith(".command"))
        or (name.startswith("man.") and name.endswith(".cmd"))
        or (name.startswith("merge.") and name.endswith(".driver"))
        or (name.startswith("mergetool.") and name.endswith(".cmd"))
        or (name.startswith("sendemail.") and name.endswith("cmd"))
        or (name.startswith("submodule.") and name.endswith(".update"))
        or (name.startswith("trailer.") and name.endswith((".cmd", ".command")))
    )


def _reject_external_hardlinks(checkout: Path) -> None:
    _reject_external_hardlinks_in_tree(
        checkout,
        skip_top_level_git=True,
        reject_nonregular=False,
    )


def _reject_external_hardlinks_in_tree(
    root: Path,
    *,
    skip_top_level_git: bool,
    reject_nonregular: bool,
) -> None:
    identities: dict[tuple[int, int], tuple[int, int]] = {}
    pending = [root]
    while pending:
        directory = pending.pop()
        try:
            entries = tuple(os.scandir(directory))
        except OSError:
            raise ValueError("could not inspect repository files") from None
        for entry in entries:
            if skip_top_level_git and directory == root and entry.name == ".git":
                continue
            try:
                metadata = entry.stat(follow_symlinks=False)
            except OSError:
                raise ValueError("could not inspect repository files") from None
            if stat.S_ISDIR(metadata.st_mode) and not stat.S_ISLNK(metadata.st_mode):
                pending.append(Path(entry.path))
                continue
            if not stat.S_ISREG(metadata.st_mode):
                if reject_nonregular:
                    raise ValueError("Git metadata contains an unsafe filesystem entry")
                continue
            identity = (metadata.st_dev, metadata.st_ino)
            count, expected = identities.get(identity, (0, metadata.st_nlink))
            if expected != metadata.st_nlink:
                raise ValueError("repository file link count changed")
            identities[identity] = (count + 1, expected)
    if any(count != expected for count, expected in identities.values()):
        raise ValueError("repository file has an external hard link")


def _validate_index(checkout: Path, environment: dict[str, str]) -> None:
    records = _nul_records(
        _git_bytes(
            ("ls-files", "--stage", "-z"),
            checkout,
            environment,
            max_output_bytes=_STATUS_OUTPUT_MAX_BYTES,
        )
    )
    for record in records:
        metadata, separator, _path = record.partition(b"\t")
        fields = metadata.split(b" ")
        if (
            not separator
            or len(fields) != 3
            or fields[0] not in _ALLOWED_BLOB_MODES
            or re.fullmatch(rb"[0-9a-fA-F]{40,64}", fields[1]) is None
            or fields[2] != b"0"
        ):
            raise ValueError("unsafe index entry")


def _unpushed_commit_ids(checkout: Path, environment: dict[str, str]) -> tuple[str, ...]:
    raw_commits = _git_bytes(
        ("rev-list", "--reverse", "FETCH_HEAD..HEAD"),
        checkout,
        environment,
        max_output_bytes=_STATUS_OUTPUT_MAX_BYTES,
    )
    commits: list[str] = []
    for raw_commit in raw_commits.splitlines():
        try:
            commit = raw_commit.decode("ascii", "strict")
        except UnicodeError:
            raise ValueError("invalid commit list") from None
        if _OBJECT_ID.fullmatch(commit.lower()) is None:
            raise ValueError("invalid commit list")
        commits.append(commit.lower())
    return tuple(commits)


def _reject_preexisting_unpushed_commits(checkout: Path, environment: dict[str, str]) -> None:
    if _unpushed_commit_ids(checkout, environment):
        raise ValueError("pre-existing unpushed commits are forbidden")


def _validate_unpushed_commits(checkout: Path, environment: dict[str, str]) -> None:
    for commit in _unpushed_commit_ids(checkout, environment):
        _validate_commit_tree(checkout, environment, commit)


def _validate_commit_tree(checkout: Path, environment: dict[str, str], commit: str) -> None:
    entries = _nul_records(
        _git_bytes(
            ("ls-tree", "-r", "-z", commit),
            checkout,
            environment,
            max_output_bytes=_STATUS_OUTPUT_MAX_BYTES,
        )
    )
    for entry in entries:
        metadata, separator, path = entry.partition(b"\t")
        fields = metadata.split(b" ")
        if (
            not separator
            or len(fields) != 3
            or fields[0] not in _ALLOWED_BLOB_MODES
            or fields[1] != b"blob"
            or re.fullmatch(rb"[0-9a-fA-F]{40,64}", fields[2]) is None
        ):
            raise ValueError("unsafe committed tree entry")
        _reject_forbidden_path(path)


def _backup_index(checkout: Path) -> _IndexBackup:
    index = checkout / ".git" / "index"
    mode = index.lstat().st_mode
    if stat.S_ISLNK(mode) or not stat.S_ISREG(mode):
        raise ValueError("unsafe Git index")
    descriptor, name = tempfile.mkstemp(prefix="hermes-index-", dir=index.parent)
    os.close(descriptor)
    backup = Path(name)
    try:
        shutil.copyfile(index, backup)
        os.chmod(backup, 0o600)
        return _IndexBackup(index, backup)
    except Exception:
        backup.unlink(missing_ok=True)
        raise


def _restore_index(backup: _IndexBackup) -> None:
    os.replace(backup.backup, backup.index)


def _discard_index_backup(backup: _IndexBackup) -> None:
    if not _unlink_path(backup.backup):
        _restore_index(backup)
        raise ValueError("could not clean index backup")


def _nul_records(output: bytes) -> list[bytes]:
    if not output:
        return []
    records = output.split(b"\0")
    if records.pop() != b"":
        raise ValueError("Git output is not NUL delimited")
    return records


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
        stem = folded.split(".", 1)[0]
        if (
            folded == ".git"
            or folded == ".env"
            or (folded.startswith(".env.") and folded not in _ALLOWED_ENV_TEMPLATES)
            or folded in _FORBIDDEN_DIRECTORIES
            or stem in _FORBIDDEN_CREDENTIAL_STEMS
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
        if (
            result.working_tree.parent != repo.target.parent
            or not result.working_tree.name.startswith(".hermes-repository-")
            or result.private_directory is None
            or result.private_directory.path != result.working_tree
        ):
            raise ValueError("synchronization result path is invalid")
    elif result.private_directory is not None:
        raise ValueError("canonical synchronization result owns private cleanup")


def _validate_working_tree(repo: SharedRepository, checkout: Path, commit: str) -> None:
    if not _looks_like_checkout(checkout):
        raise ValueError("working tree is not safe")
    askpass: Path | None = None
    try:
        askpass = _create_askpass(checkout.parent)
        environment = _git_environment(_LOCAL_VALIDATION_AUTH, askpass)
        _verify_checkout_identity(repo, checkout, environment)
        _validate_index(checkout, environment)
        _validate_commit_tree(checkout, environment, commit)
        _reject_external_hardlinks(checkout)
        if _git_bytes(
            ("status", "--porcelain=v1", "-z", "--untracked-files=all"),
            checkout,
            environment,
            max_output_bytes=_STATUS_OUTPUT_MAX_BYTES,
        ) != b"":
            raise ValueError("working tree is dirty")
        if _head_commit(checkout, environment) != commit:
            raise ValueError("working tree commit mismatch")
    finally:
        if askpass is not None and not _unlink_path(askpass):
            raise ValueError("could not clean local validation askpass")


def _move_verified_working_tree(
    repo: SharedRepository,
    source: Path,
    commit: str,
) -> None:
    source_identity = _directory_identity(source)
    if _optional_empty_directory_identity(repo.target) is not None:
        raise ValueError("canonical target already exists")
    flags = os.O_RDONLY | os.O_CLOEXEC
    if hasattr(os, "O_DIRECTORY"):
        flags |= os.O_DIRECTORY
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    descriptor = os.open(source, flags)
    source_parent_descriptor: int | None = None
    target_parent_descriptor: int | None = None
    try:
        source_parent_descriptor = os.open(source.parent, flags)
        target_parent_descriptor = os.open(repo.target.parent, flags)
        if _identity_from_stat(os.fstat(descriptor)) != source_identity:
            raise ValueError("working tree identity changed")
        if _directory_identity(source) != source_identity:
            raise ValueError("working tree path was swapped")
        if _optional_empty_directory_identity(repo.target) is not None:
            raise ValueError("canonical target changed before move")
        _reject_unsafe_git_metadata(source)
        _reject_external_hardlinks(source)
        if _directory_identity(source) != source_identity:
            raise ValueError("working tree identity changed before move")
        _rename_noreplace(
            source_parent_descriptor,
            source.name,
            target_parent_descriptor,
            repo.target.name,
        )
        try:
            if _directory_identity(repo.target) != source_identity:
                raise ValueError("moved working tree identity changed")
            _validate_working_tree(repo, repo.target, commit)
        except Exception:
            _rollback_failed_move(source, repo.target)
            raise
    finally:
        if target_parent_descriptor is not None:
            os.close(target_parent_descriptor)
        if source_parent_descriptor is not None:
            os.close(source_parent_descriptor)
        os.close(descriptor)


def _copy_working_tree_for_publication(
    repo: SharedRepository,
    source: Path,
    commit: str,
) -> PrivateDirectory:
    copy = create_private_directory(
        repo.target.parent,
        prefix=".hermes-repository-",
    )
    try:
        shutil.copytree(
            source,
            copy.path,
            symlinks=True,
            dirs_exist_ok=True,
        )
        _validate_working_tree(repo, copy.path, commit)
        return copy
    except Exception:
        if not copy.cleanup():
            raise ValueError("could not clean private repository copy") from None
        raise


def _rollback_failed_move(source: Path, target: Path) -> None:
    if _lexists(source) or not _lexists(target):
        raise ValueError("could not roll back invalid working tree move")
    os.replace(target, source)


def _directory_identity(path: Path) -> _PathIdentity:
    identity = _identity_from_stat(path.lstat())
    if identity.file_type != stat.S_IFDIR:
        raise ValueError("working tree is not a directory")
    return identity


def _optional_empty_directory_identity(path: Path) -> _PathIdentity | None:
    if not _lexists(path):
        return None
    identity = _directory_identity(path)
    with os.scandir(path) as entries:
        if next(entries, None) is not None:
            raise ValueError("canonical target contains data")
    return identity


def _identity_from_stat(value: os.stat_result) -> _PathIdentity:
    return _PathIdentity(value.st_dev, value.st_ino, stat.S_IFMT(value.st_mode))


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


def _remove_legacy_target(
    repo: SharedRepository,
    tx: Transaction,
    changed: list[Path],
    *,
    allow_populated: bool,
) -> None:
    legacy = repo.legacy_target
    if legacy is None:
        return
    if not _lexists(legacy):
        return
    mode = legacy.lstat().st_mode
    if stat.S_ISLNK(mode):
        if not _is_correct_legacy_link(repo):
            raise ValueError("unexpected legacy target")
    elif stat.S_ISDIR(mode):
        with os.scandir(legacy) as entries:
            if next(entries, None) is not None and not allow_populated:
                raise ValueError("legacy target contains data")
    else:
        raise ValueError("unexpected legacy target")
    _snapshot(tx, legacy)
    if stat.S_ISDIR(mode):
        if not _remove_private_tree(legacy):
            raise ValueError("could not remove legacy repository")
    else:
        legacy.unlink()
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


def _repository_data_root(repo: SharedRepository) -> Path:
    return repo.target.parent.parent


def _require_safe_repository_parents(repo: SharedRepository) -> None:
    data_root = _repository_data_root(repo)
    _ensure_safe_directory(data_root)
    _require_safe_managed_directory(repo.target.parent, data_root)
    if repo.legacy_target is not None:
        _require_safe_managed_directory(repo.legacy_target.parent, data_root)


def _require_safe_checkout_location(repo: SharedRepository, checkout: Path) -> None:
    _require_safe_repository_parents(repo)
    allowed = {repo.target}
    if repo.legacy_target is not None:
        allowed.add(repo.legacy_target)
    staged = (
        checkout.parent == repo.target.parent
        and checkout.name.startswith(".hermes-repository-")
    )
    if checkout not in allowed and not staged:
        raise ValueError("checkout is outside the managed repository paths")
    if not _safe_directory(checkout):
        raise ValueError("checkout directory is unsafe")


def _require_safe_managed_directory(path: Path, data_root: Path) -> None:
    try:
        relative = path.relative_to(data_root)
    except ValueError:
        raise ValueError("managed path is outside the data root") from None
    if not _safe_directory(data_root):
        raise ValueError("data root is unsafe")
    current = data_root
    for component in relative.parts:
        current /= component
        if not _lexists(current):
            return
        if not _safe_directory(current):
            raise ValueError("managed parent is unsafe")


def _ensure_safe_managed_directory(path: Path, data_root: Path) -> None:
    _ensure_safe_directory(data_root)
    try:
        relative = path.relative_to(data_root)
    except ValueError:
        raise ValueError("managed path is outside the data root") from None
    current = data_root
    for component in relative.parts:
        current /= component
        if _lexists(current):
            if not _safe_directory(current):
                raise ValueError("managed directory is unsafe")
            continue
        current.mkdir(mode=0o700)


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


def _unlink_path(path: Path) -> bool:
    try:
        path.unlink()
    except OSError:
        return False
    return not _lexists(path)


def _remove_private_tree(path: Path) -> bool:
    try:
        mode = path.lstat().st_mode
        if stat.S_ISDIR(mode) and not stat.S_ISLNK(mode):
            shutil.rmtree(path)
        else:
            path.unlink()
    except OSError:
        return False
    return not _lexists(path)
