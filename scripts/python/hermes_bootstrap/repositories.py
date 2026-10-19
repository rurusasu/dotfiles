"""Synchronization and publication for shared Hermes repositories."""

from __future__ import annotations

import os
import re
import shutil
import stat
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

from .errors import RepositoryError
from .filesystem import PrivateDirectory, create_private_directory
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
_FORBIDDEN_GIT_METADATA = (
    Path("commondir"),
    Path("info/grafts"),
    Path("objects/info/alternates"),
    Path("objects/info/http-alternates"),
)

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


@dataclass(frozen=True)
class _IndexBackup:
    index: Path
    backup: Path


def synchronize_remote(repo: SharedRepository, auth: GitAuth) -> RemoteSyncResult:
    """Synchronize one declared repository before publishing a new checkout."""

    stage: PrivateDirectory | None = None
    askpass: Path | None = None
    succeeded = False
    try:
        _validate_declaration(repo, auth)
        data_root = _repository_data_root(repo)
        _require_safe_repository_parents(repo)
        working_tree = _selected_working_tree(repo)
        if working_tree is None:
            _ensure_safe_managed_directory(repo.target.parent, data_root)
            stage = create_private_directory(
                repo.target.parent,
                prefix=".hermes-repository-",
            )
            working_tree = stage.path
        askpass = _create_askpass(working_tree.parent)
        environment = _git_environment(auth, askpass)
        if stage is not None:
            commit = _initialize_checkout(repo, stage.path, environment)
            pushed = False
        else:
            _verify_checkout_identity(repo, working_tree, _local_git_environment(environment))
            commit, pushed = _synchronize_checkout(repo, working_tree, environment)
        result = RemoteSyncResult(repo.name, commit, pushed, working_tree, stage)
        succeeded = True
        return result
    except Exception:
        raise RepositoryError("could not synchronize shared repository") from None
    finally:
        cleanup_failed = askpass is not None and not _unlink_path(askpass)
        if stage is not None and (not succeeded or cleanup_failed):
            cleanup_failed = not stage.cleanup() or cleanup_failed
        if cleanup_failed:
            raise RepositoryError("could not clean private repository resources") from None


def apply_shared_working_tree(repo: SharedRepository, result: RemoteSyncResult) -> None:
    """Publish a synchronized checkout while preserving an existing target."""

    try:
        _apply_shared_working_tree(repo, result)
    except Exception:
        raise RepositoryError("could not apply the shared repository working tree") from None


def _apply_shared_working_tree(
    repo: SharedRepository, result: RemoteSyncResult
) -> None:
    _validate_result(repo, result)
    _require_safe_repository_parents(repo)
    canonical_real = _real_data_state(repo.target)

    working_tree = result.working_tree
    if working_tree is None:
        raise ValueError("missing synchronized checkout")
    if canonical_real and working_tree != repo.target:
        raise ValueError("canonical target already exists")
    if not canonical_real:
        _ensure_safe_managed_directory(repo.target.parent, _repository_data_root(repo))
        _move_verified_working_tree(repo, working_tree)


def synchronize_named_repository(
    name: str,
    manifest: BootstrapManifest,
    auth: GitAuth,
) -> RemoteSyncResult:
    """Synchronize a declared repository's canonical runtime checkout."""

    selected = next((repo for repo in manifest.shared_repositories if repo.name == name), None)
    if selected is None:
        raise RepositoryError("unknown shared repository name")
    if not _looks_like_checkout(selected.target):
        raise RepositoryError("the canonical shared repository checkout is unavailable")
    return synchronize_remote(selected, auth)


def _validate_declaration(repo: SharedRepository, auth: GitAuth) -> None:
    data_root = repo.target.parent.parent if isinstance(repo, SharedRepository) else None
    if (
        not isinstance(repo, SharedRepository)
        or _REPOSITORY_NAME.fullmatch(repo.name) is None
        or not _valid_auth(auth)
        or _remote_identity(repo.source) is None
        or not _valid_ref(repo.ref)
        or not repo.target.is_absolute()
        or repo.target.name != repo.name
        or repo.target.parent.name != "shared"
        or repo.target != data_root / "shared" / repo.name
    ):
        raise ValueError("invalid repository declaration")


def _selected_working_tree(repo: SharedRepository) -> Path | None:
    return repo.target if _real_data_state(repo.target) else None


def _initialize_checkout(repo: SharedRepository, checkout: Path, environment: dict[str, str]) -> str:
    _require_safe_checkout_location(repo, checkout)
    _require_git_success(("init", "--quiet"), checkout, environment)
    _require_git_success(("remote", "add", "origin", "--", repo.source), checkout, environment)
    remote_commit = _fetch_declared_commit(repo, checkout, environment)
    _validate_commit_tree(checkout, _local_git_environment(environment), remote_commit)
    _require_git_success(("checkout", "--detach", remote_commit), checkout, environment)
    return remote_commit


def _verify_checkout_identity(repo: SharedRepository, checkout: Path, environment: dict[str, str]) -> None:
    if not _looks_like_checkout(checkout):
        raise ValueError("not a checkout")
    _require_safe_checkout_location(repo, checkout)
    _reject_unsafe_git_metadata(checkout)
    _reject_hardlinks(checkout)
    _reject_redirecting_local_config(checkout, environment)
    _reject_replace_refs(checkout, environment)
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
    status_output = _git_bytes(
        ("status", "--porcelain=v1", "-z", "--untracked-files=all"),
        checkout,
        local_environment,
        max_output_bytes=_STATUS_OUTPUT_MAX_BYTES,
    )
    _reject_forbidden_status_paths(status_output)
    _validate_index(checkout, local_environment)
    remote_commit = _fetch_declared_commit(repo, checkout, environment)
    _validate_commit_tree(checkout, local_environment, remote_commit)
    _reject_preexisting_unpushed_commits(checkout, local_environment)
    staged = b""
    if status_output:
        backup = _backup_index(checkout)
        try:
            _require_git_success(("add", "-A", "--", "."), checkout, local_environment)
            _validate_index(checkout, local_environment)
            staged = _git_bytes(
                ("diff", "--cached", "--name-only", "-z"),
                checkout,
                local_environment,
                max_output_bytes=_STATUS_OUTPUT_MAX_BYTES,
            )
        except Exception:
            _restore_index(backup)
            raise
        _discard_index_backup(backup)
    created_commit = False
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
            local_environment,
        )
        created_commit = True
    try:
        if _try_git_bytes(("rebase", "FETCH_HEAD"), checkout, local_environment) is None:
            if _try_git_bytes(("rebase", "--abort"), checkout, local_environment) is None:
                raise ValueError("could not abort rebase")
            raise ValueError("rebase failed")
        head = _head_commit(checkout, local_environment)
        ahead = _git_ascii(("rev-list", "--count", "FETCH_HEAD..HEAD"), checkout, local_environment)
        if ahead is None or not ahead.isdecimal():
            raise ValueError("could not count local commits")
        pushed = int(ahead) > 0
        if pushed:
            _require_git_success(
                ("push", "--", repo.source, f"HEAD:{repo.ref}"), checkout, environment
            )
        return head, pushed
    except Exception:
        if created_commit:
            _try_git_bytes(("reset", "--mixed", remote_commit), checkout, local_environment)
        raise


def _fetch_declared_commit(repo: SharedRepository, checkout: Path, environment: dict[str, str]) -> str:
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


def _reject_unsafe_git_metadata(checkout: Path) -> None:
    metadata_root = checkout / ".git"
    if any(_lexists(metadata_root / relative) for relative in _FORBIDDEN_GIT_METADATA):
        raise ValueError("external Git metadata is forbidden")
    _reject_hardlinks_in_tree(
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


def _reject_hardlinks(checkout: Path) -> None:
    _reject_hardlinks_in_tree(
        checkout,
        skip_top_level_git=True,
        reject_nonregular=False,
    )


def _reject_hardlinks_in_tree(
    root: Path,
    *,
    skip_top_level_git: bool,
    reject_nonregular: bool,
) -> None:
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
            if metadata.st_nlink != 1:
                raise ValueError("repository file has a hard link")


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


def _reject_preexisting_unpushed_commits(checkout: Path, environment: dict[str, str]) -> None:
    if _git_bytes(
        ("rev-list", "--reverse", "FETCH_HEAD..HEAD"),
        checkout,
        environment,
        max_output_bytes=_STATUS_OUTPUT_MAX_BYTES,
    ):
        raise ValueError("pre-existing unpushed commits are forbidden")


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


def _move_verified_working_tree(repo: SharedRepository, source: Path) -> None:
    if _lexists(repo.target):
        raise ValueError("canonical target already exists")
    source.rename(repo.target)


def _real_data_state(path: Path) -> bool:
    if not _lexists(path):
        return False
    mode = path.lstat().st_mode
    if stat.S_ISLNK(mode):
        raise ValueError("unexpected symlink")
    if not stat.S_ISDIR(mode):
        raise ValueError("shared repository target is not a directory")
    with os.scandir(path) as entries:
        return next(entries, None) is not None


def _looks_like_checkout(path: Path) -> bool:
    if not _safe_directory(path):
        return False
    metadata = path / ".git"
    return _safe_directory(metadata)


def _ensure_safe_directory(path: Path) -> None:
    if not path.is_absolute() or path != Path(os.path.normpath(path)):
        raise ValueError("directory path is not canonical")
    missing: list[Path] = []
    current = path
    while not _lexists(current):
        missing.append(current)
        current = current.parent
    if not all(_safe_directory(directory) for directory in (*current.parents, current)):
        raise ValueError("unsafe directory")
    for directory in reversed(missing):
        directory.mkdir(mode=0o700)


def _repository_data_root(repo: SharedRepository) -> Path:
    return repo.target.parent.parent


def _require_safe_repository_parents(repo: SharedRepository) -> None:
    data_root = _repository_data_root(repo)
    _ensure_safe_directory(data_root)
    _require_safe_managed_directory(repo.target.parent, data_root)


def _require_safe_checkout_location(repo: SharedRepository, checkout: Path) -> None:
    _require_safe_repository_parents(repo)
    allowed = {repo.target}
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


def _unlink_path(path: Path) -> bool:
    try:
        path.unlink()
    except OSError:
        return False
    return not _lexists(path)
