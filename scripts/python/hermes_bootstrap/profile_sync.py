"""Publish exact local Hermes profile snapshots with Git plumbing."""

from __future__ import annotations

import hashlib
import re
import stat
import tempfile
import unicodedata
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Literal
from urllib.parse import quote

import yaml

from .distributions import without_bootstrap_managed_config
from .filesystem import PrivateDirectory, create_private_directory
from .git import (
    _create_askpass,
    _git_environment,
    _remote_identity,
    _run_git_bytes,
    _valid_auth,
    _valid_ref,
)
from .github import GitAuth
from .models import BootstrapManifest, DistributionSource
from .profile_snapshot import (
    ProfileSnapshot,
    ProfileSnapshotError,
    prepare_profile_snapshots,
)

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


class _DeletionLimitExceeded(Exception):
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
                diff=ProfileDiff(),
                category=category,
                message=message,
            )
            for profile in profiles
        ),
        exit_code=exit_code,
    )


def synchronize_prepared_profiles(
    snapshots: tuple[ProfileSnapshot, ...], auth: GitAuth, *, dry_run: bool
) -> ProfileSyncReport:
    """Synchronize each immutable profile projection in prepared order."""

    results = tuple(
        _synchronize_one_boundary(snapshot, auth, dry_run)
        for snapshot in snapshots
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
    scratch: PrivateDirectory | None = None
    report: ProfileSyncReport
    try:
        _validate_manifest_profiles(manifest)
        # Staging lives outside Hermes home and is removed after publication.
        scratch = create_private_directory(
            _profile_snapshot_scratch_parent(manifest.data_root),
            prefix=".hermes-profile-snapshots-",
        )
        prepared = prepare_profile_snapshots(manifest, scratch.path)
        report = synchronize_prepared_profiles(prepared, auth, dry_run=dry_run)
    except ProfileSnapshotError as error:
        invalid_profile = error.profile
        invalid_category = error.category
        report = _profile_preflight_failure(
            profiles, invalid_profile, invalid_category, dry_run=dry_run
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


def _profile_snapshot_scratch_parent(data_root: Path) -> Path:
    """Return a real temporary parent that is outside the Hermes data root."""

    try:
        scratch_parent = Path(tempfile.gettempdir()).resolve(strict=True)
        resolved_data_root = data_root.resolve(strict=True)
    except OSError as error:
        raise ValueError("invalid profile snapshot scratch parent") from error
    if scratch_parent == resolved_data_root or scratch_parent.is_relative_to(
        resolved_data_root
    ):
        raise ValueError("profile snapshot scratch parent is inside Hermes data root")
    return scratch_parent


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
    repository: PrivateDirectory | None = None
    askpass: Path | None = None
    try:
        _validate_snapshot_declaration(snapshot, auth, data_root)
        repository = create_private_directory(
            Path(tempfile.gettempdir()),
            prefix=".hermes-profile-sync-",
        )
        repository_path = repository.path
        askpass = _create_askpass(Path(tempfile.gettempdir()))
        environment = _git_environment(auth, askpass)
        attempt = _exact_tree_attempt(
            snapshot,
            repository_path,
            environment,
        )
        remote_tree = _git_ascii(
            ("rev-parse", "FETCH_HEAD^{tree}"),
            repository_path,
            environment,
        )
        if remote_tree is None:
            raise ValueError("remote tree unavailable")
        if attempt.tree == remote_tree:
            outcome = ProfileSyncResult(
                name=declaration.name,
                status="unchanged",
                commit=attempt.remote_commit,
                diff=ProfileDiff(),
                category="unchanged",
                message="profile snapshot already published",
            )
        else:
            diff = _profile_diff(
                repository_path,
                environment,
                auth,
                attempt.remote_commit,
            )
            bootstrap_config_only = _is_bootstrap_config_only_difference(
                diff,
                attempt.remote_commit,
                repository_path,
                environment,
            )
            if bootstrap_config_only:
                outcome = ProfileSyncResult(
                    name=declaration.name,
                    status="unchanged",
                    commit=attempt.remote_commit,
                    diff=ProfileDiff(),
                    category="unchanged",
                    message="profile snapshot only differs by bootstrap configuration",
                )
            elif dry_run:
                commit = attempt.remote_commit
                category = "dry_run"
                message = "profile snapshot changes detected"
            else:
                if len(diff.deleted) > declaration.max_deleted_paths:
                    raise _DeletionLimitExceeded
                commit = _commit_and_push(
                    snapshot,
                    attempt,
                    repository_path,
                    environment,
                )
                category = "published"
                message = "profile snapshot published"
            if not bootstrap_config_only:
                outcome = ProfileSyncResult(
                    name=declaration.name,
                    status="changed",
                    commit=commit,
                    diff=diff,
                    category=category,
                    message=message,
                )
    except _PushRejected:
        outcome = _failed(
            snapshot,
            "push_rejected",
            "profile publication was rejected; rerun sync-profiles",
        )
    except _DeletionLimitExceeded:
        outcome = _failed(
            snapshot,
            "deletion_limit_exceeded",
            "profile publication exceeded the configured deletion limit",
        )
    except Exception:
        outcome = _failed(snapshot, "repository", "profile snapshot synchronization failed")

    resources: list[tuple[Callable, object]] = []
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
    branch_ref = _validated_branch_ref(
        declaration.ref, repository, environment
    )
    _require_git(
        ("fetch", "--no-tags", "--", declaration.source, branch_ref),
        repository,
        environment,
    )
    remote_commit = _git_object_id(
        ("rev-parse", "--verify", "FETCH_HEAD^{commit}"), repository, environment
    )
    _require_git(("read-tree", "--empty"), repository, environment)
    _copy_snapshot(snapshot, repository)
    _require_git(("add", "-A", "--", "."), repository, environment)
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


def _is_bootstrap_config_only_difference(
    diff: ProfileDiff,
    remote_commit: str,
    repository: Path,
    environment: dict[str, str],
) -> bool:
    if diff != ProfileDiff(modified=(PurePosixPath("config.yaml"),)):
        return False
    try:
        local = yaml.safe_load((repository / "config.yaml").read_text(encoding="utf-8"))
        remote = yaml.safe_load(
            _git_bytes(
                ("show", f"{remote_commit}:config.yaml"),
                repository,
                environment,
            ).decode("utf-8")
        )
    except (OSError, UnicodeError, ValueError, yaml.YAMLError):
        return False
    return (
        isinstance(local, dict)
        and isinstance(remote, dict)
        and without_bootstrap_managed_config(local)
        == without_bootstrap_managed_config(remote)
    )


def _reported_path(raw: bytes, auth: GitAuth) -> PurePosixPath:
    try:
        text = raw.decode("utf-8", "strict")
    except UnicodeError:
        return _escaped_reported_path(raw)
    path = PurePosixPath(text)
    if (
        not text
        or path.is_absolute()
        or path.as_posix() != text
        or any(part in {"", ".", ".."} for part in path.parts)
        or not _visible_path_text(text)
        or auth.token in text
        or quote(auth.token, safe="") in text
    ):
        return _escaped_reported_path(raw)
    return path


def _visible_path_text(text: str) -> bool:
    return all(
        character == " "
        or (
            character.isprintable()
            and unicodedata.category(character)[0] not in {"C", "M", "Z"}
        )
        for character in text
    )


def _escaped_reported_path(raw: bytes) -> PurePosixPath:
    digest = hashlib.sha256(raw).hexdigest()
    return PurePosixPath(".git-path-bytes", f"sha256-{digest}")


def _commit_and_push(
    snapshot: ProfileSnapshot,
    attempt: _Attempt,
    repository: Path,
    environment: dict[str, str],
) -> str:
    commit = _create_commit(
        snapshot, attempt.tree, attempt.remote_commit, repository, environment
    )
    if not _push_commit(snapshot, commit, repository, environment):
        raise _PushRejected
    return commit


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


def _copy_snapshot(snapshot: ProfileSnapshot, repository: Path) -> None:
    _write_file(repository / ".gitignore", snapshot.gitignore_bytes, 0o644)
    _write_file(repository / "distribution.yaml", snapshot.manifest_bytes, 0o644)
    for entry in snapshot.entries:
        source = snapshot.root.joinpath(*entry.path.parts)
        destination = repository.joinpath(*entry.path.parts)
        content = source.read_bytes()
        _write_file(destination, content, entry.mode)


def _write_file(path: Path, content: bytes, mode: int) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    path.write_bytes(content)
    path.chmod(mode)


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
        diff=ProfileDiff(),
        category=category,
        message=message,
    )


def _cleanup_resources(
    resources: tuple[tuple[Callable, object], ...]
) -> bool:
    failed = False
    for cleanup, path in resources:
        try:
            if not cleanup(path):
                failed = True
        except Exception:
            failed = True
    return failed


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


def _remove_tree(directory: object) -> bool:
    if not isinstance(directory, PrivateDirectory):
        return False
    return directory.cleanup()
