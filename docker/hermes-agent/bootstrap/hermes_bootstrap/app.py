"""Hermes bootstrap command orchestration and installed-layout validation."""

from __future__ import annotations

import json
import os
import re
import stat
from collections.abc import Mapping
from dataclasses import dataclass, replace
from io import StringIO
from pathlib import Path, PurePosixPath
from typing import Callable, TextIO

from dotenv.parser import parse_stream

from . import profile_sync
from .distributions import (
    _normalize_owned_paths,
    _read_profile_manifest_at,
    apply_profile_distribution,
    apply_root_distribution,
)
from .envfiles import (
    _is_reusable_api_server_key,
    _is_reusable_signing_secret,
    API_SERVER_KEYS,
    DASHBOARD_KEYS,
    GITHUB_KEYS,
    SLACK_KEYS,
    build_dashboard_environment,
    build_profile_environment,
    merge_env_file,
    read_environment_values,
)
from .engine_lock import EngineLock
from .errors import (
    ApplyError,
    BootstrapError,
    CredentialError,
    RepositoryError,
    RollbackError,
    ValidationError,
)
from .filesystem import (
    PrivateDirectory,
    create_private_directory,
    open_absolute_directory,
)
from .git import _remote_identity, _same_remote_identity, stage_distribution
from .github import GitAuth, GitHubClient
from .manifest import load_manifest
from .models import BootstrapManifest, DistributionSource, SharedRepository
from .payload import SecretRedactor, build_secret_plan, read_secret_payload
from .profile_snapshot import (
    ProfileSnapshotError,
    prepare_profile_snapshots,
)
from .profile_sync import ProfileSyncReport
from .repositories import (
    RemoteSyncResult,
    apply_shared_working_tree,
    synchronize_named_repository,
    synchronize_remote,
)
from .source_contracts import validate_chrome_mcp_sources
from .transaction import Transaction


_ENV_LIMIT = 1024 * 1024
_OBJECT_ID = re.compile(r"[0-9a-f]{40}(?:[0-9a-f]{24})?\Z")
_SLACK_BOT_TOKEN = re.compile(r"xoxb-[A-Za-z0-9-]+\Z")
_SLACK_APP_TOKEN = re.compile(r"xapp-[A-Za-z0-9-]+\Z")
_MANAGED_ENV_KEYS = GITHUB_KEYS | DASHBOARD_KEYS | API_SERVER_KEYS | SLACK_KEYS
_PLAINTEXT_DASHBOARD_PASSWORD = "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD"
_failpoint: Callable[[str], None] = lambda _name: None


@dataclass(frozen=True)
class _ApplyOutcome:
    result: dict[str, object] | None = None
    error_type: type[BootstrapError] | None = None
    message: str | None = None
    profile_sync_report: ProfileSyncReport | None = None


def secret_plan(manifest_path: Path) -> dict[str, object]:
    """Return the deterministic non-secret adapter plan."""

    return build_secret_plan(load_manifest(manifest_path))


def apply(manifest_path: Path, input_stream: TextIO) -> dict[str, object]:
    """Perform one fully staged bootstrap transaction without printing secrets."""

    manifest = load_manifest(manifest_path)
    with EngineLock.acquire(manifest.data_root) as engine_lock:
        engine_lock.require_held()
        Transaction.recover_if_needed(manifest.data_root)
        outcome = _apply_sensitive_boundary(manifest_path, manifest, input_stream)
    del input_stream
    if outcome.error_type is not None:
        error_type = outcome.error_type
        message = outcome.message or "bootstrap apply failed"
        profile_sync_report = outcome.profile_sync_report
        del outcome
        error = error_type(message)
        if profile_sync_report is not None:
            setattr(error, "profile_sync_report", profile_sync_report)
        del profile_sync_report
        raise error from None
    result = outcome.result
    del outcome
    if result is None:
        raise ApplyError("bootstrap apply failed") from None
    return result


def _apply_sensitive_boundary(
    manifest_path: Path, manifest: BootstrapManifest, input_stream: TextIO
) -> _ApplyOutcome:
    try:
        return _ApplyOutcome(result=_apply_sensitive(manifest_path, manifest, input_stream))
    except BootstrapError as error:
        error_type = (
            RepositoryError if isinstance(error, RepositoryError) else type(error)
        )
        report = getattr(error, "profile_sync_report", None)
        outcome = _ApplyOutcome(
            error_type=error_type,
            message=str(error),
            profile_sync_report=(
                report if isinstance(report, ProfileSyncReport) else None
            ),
        )
        del error
        return outcome
    except Exception:
        return _ApplyOutcome(error_type=ApplyError, message="bootstrap apply failed")


def _apply_sensitive(
    manifest_path: Path, manifest: BootstrapManifest, input_stream: TextIO
) -> dict[str, object]:
    """Own all secret-bearing values behind the non-raising boundary."""

    scratch: PrivateDirectory | None = None
    remote_results: list[tuple[SharedRepository, RemoteSyncResult]] = []
    profile_report: ProfileSyncReport | None = None
    tx: Transaction | None = None
    primary: BootstrapError | None = None
    rollback_error: RollbackError | None = None
    result: dict[str, object] | None = None
    try:
        secrets = read_secret_payload(input_stream, manifest)
        auth = GitAuth(secrets.github_token, secrets.redactor)
        _validate_remote_credentials(manifest, auth)
        dashboard = _validate_profile_credentials(
            manifest,
            secrets,
            read_environment_values(
                manifest.data_root / ".env", DASHBOARD_KEYS | API_SERVER_KEYS
            ),
        )

        scratch = _private_scratch(manifest.data_root)
        prepared = prepare_profile_snapshots(
            manifest,
            scratch.path,
            allow_missing=True,
        )
        missing_names = frozenset(source.name for source in prepared.missing)
        sync_prepared = replace(prepared, missing=())
        profile_report = profile_sync.synchronize_prepared_profiles(
            sync_prepared, auth, dry_run=False
        )
        if profile_report.exit_code != 0:
            failed = ",".join(
                item.name
                for item in profile_report.profiles
                if item.status == "failed"
            )
            raise RepositoryError(
                f"named profile repository sync failed: {failed}"
            )

        commit_by_name = {
            item.name: item.commit
            for item in profile_report.profiles
            if item.commit is not None
        }
        status_by_name = {
            item.name: item.status for item in profile_report.profiles
        }
        profile_sync_summary: dict[str, str] = {}
        profile_sources: list[DistributionSource] = []
        for source in manifest.profiles:
            if source.name in missing_names:
                exact = source
                profile_sync_summary[source.name] = "installed"
            else:
                commit = commit_by_name.get(source.name)
                status = status_by_name.get(source.name)
                if commit is None or status is None:
                    raise RepositoryError(
                        f"named profile repository sync failed: {source.name}"
                    )
                exact = replace(source, ref=commit)
                profile_sync_summary[source.name] = status
            profile_sources.append(exact)

        root_stage = stage_distribution(
            manifest.root_distribution,
            scratch.path,
            auth,
        )
        profile_stages = [
            stage_distribution(source, scratch.path, auth)
            for source in profile_sources
        ]
        validate_chrome_mcp_sources([root_stage, *profile_stages])
        for repo in manifest.shared_repositories:
            remote_results.append((repo, synchronize_remote(repo, auth)))

        tx = Transaction.begin(manifest.data_root)
        apply_root_distribution(root_stage, manifest.data_root, tx)
        _failpoint("root-apply")
        for stage in profile_stages:
            apply_profile_distribution(stage, manifest.data_root, tx)
            _failpoint(f"profile-apply:{stage.declaration.name}")
        for repo, result in remote_results:
            apply_shared_working_tree(repo, result, tx)
            _failpoint(f"shared-apply:{repo.name}")

        for profile, target in _environment_targets(manifest):
            environment = build_profile_environment(profile, secrets, dashboard)
            env_path = target / ".env"
            tx.snapshot(env_path)
            merge_env_file(env_path, environment, _MANAGED_ENV_KEYS - set(environment))
            _failpoint(f"env-merge:{profile}")

        del dashboard
        _validate_installed_layout(manifest, allow_active_transaction=True)
        _failpoint("final-validation")
        _failpoint("commit-cleanup")
        tx.commit()
        tx = None
        result = {
            "status": "applied",
            "profiles": [profile.name for profile in manifest.profiles],
            "repositories": [repo.name for repo in manifest.shared_repositories],
            "profile_sync": profile_sync_summary,
        }
    except ProfileSnapshotError as error:
        profile_report = profile_sync._profile_preflight_failure(
            manifest.profiles,
            error.profile,
            error.category,
            dry_run=False,
        )
        primary = RepositoryError(str(error))
    except BootstrapError as error:
        primary = error
    except Exception:
        primary = ApplyError("bootstrap apply failed")
    finally:
        if tx is not None:
            try:
                tx.rollback()
            except RollbackError as error:
                rollback_error = error
            except Exception:
                rollback_error = RollbackError("could not roll back managed paths")
        cleanup_failed = not _cleanup_apply_resources(scratch, remote_results, manifest.data_root)

    if rollback_error is not None:
        raise _attach_profile_sync_report(rollback_error, profile_report)
    if cleanup_failed:
        raise _attach_profile_sync_report(
            ApplyError("could not clean bootstrap staging resources"),
            profile_report,
        )
    if primary is not None:
        raise _attach_profile_sync_report(primary, profile_report)
    if result is None:
        raise ApplyError("bootstrap apply failed")
    return result


def _attach_profile_sync_report(
    error: BootstrapError, report: ProfileSyncReport | None
) -> BootstrapError:
    if report is not None:
        setattr(error, "profile_sync_report", report)
    return error


def validate(manifest_path: Path) -> dict[str, object]:
    """Validate the installed runtime without network, recovery, or mutation."""

    manifest = load_manifest(manifest_path)
    result = _validate_installed_layout(manifest, allow_active_transaction=False)
    return {"status": "valid", **result}


def sync_repository(
    manifest_path: Path, name: str, environ: Mapping[str, str] | None = None
) -> dict[str, object]:
    """Synchronize a declared canonical checkout using a runtime token."""

    manifest = load_manifest(manifest_path)
    environment = os.environ if environ is None else environ
    return _sync_repository_boundary(manifest, name, environment)


def sync_profiles(
    manifest_path: Path,
    *,
    dry_run: bool,
    environ: Mapping[str, str] | None = None,
) -> ProfileSyncReport:
    """Synchronize every configured local profile using a runtime token."""

    manifest = load_manifest(manifest_path)
    environment = os.environ if environ is None else environ
    return _sync_profiles_boundary(manifest, dry_run=dry_run, environ=environment)


def _sync_profiles_boundary(
    manifest: BootstrapManifest,
    *,
    dry_run: bool,
    environ: Mapping[str, str],
) -> ProfileSyncReport:
    token: str | None = None
    try:
        with EngineLock.acquire(manifest.data_root) as engine_lock:
            engine_lock.require_held()
            token = _runtime_token(manifest, environ)
            auth = GitAuth(token, SecretRedactor((token,)))
            return profile_sync.synchronize_profiles(manifest, auth, dry_run=dry_run)
    except CredentialError as error:
        error = profile_sync._scrub_exception_graph(error)
        return profile_sync.failed_profile_report(
            manifest.profiles,
            dry_run=dry_run,
            category="credentials_unavailable",
            message="GitHub credentials are unavailable",
            exit_code=CredentialError.exit_code,
        )
    except Exception as error:
        error = profile_sync._scrub_exception_graph(error)
        return profile_sync.failed_profile_report(
            manifest.profiles,
            dry_run=dry_run,
            category="repository",
            message="profile synchronization failed",
            exit_code=RepositoryError.exit_code,
        )
    finally:
        token = None


def _sync_repository_boundary(
    manifest: BootstrapManifest, name: str, environ: Mapping[str, str]
) -> dict[str, object]:
    token: str | None = None
    try:
        with EngineLock.acquire(manifest.data_root) as engine_lock:
            engine_lock.require_held()
            token = _runtime_token(manifest, environ)
            auth = GitAuth(token, SecretRedactor((token,)))
            result = synchronize_named_repository(name, manifest, auth, require_canonical=True)
            return {"status": "synchronized", "name": result.name, "commit": result.commit, "pushed": result.pushed}
    except BootstrapError:
        raise
    except Exception:
        raise CredentialError("GitHub credentials are unavailable") from None
    finally:
        token = None


def _validate_remote_credentials(manifest: BootstrapManifest, auth: GitAuth) -> None:
    client = GitHubClient(auth)
    client.authenticated_login()
    seen: set[tuple[str, str]] = set()
    for source in (*_distributions(manifest), *manifest.shared_repositories):
        identity = _source_identity(source.source)
        if identity is None:
            raise ValidationError("declared Git source is invalid")
        if identity not in seen:
            client.assert_repository_access(*identity)
            seen.add(identity)


def _validate_profile_credentials(
    manifest: BootstrapManifest,
    secrets: object,
    existing: Mapping[str, str],
) -> Mapping[str, str]:
    """Exercise the credentials that each resulting profile will receive."""

    dashboard = build_dashboard_environment(secrets, existing)  # type: ignore[arg-type]
    for profile, _target in _environment_targets(manifest):
        environment = build_profile_environment(profile, secrets, dashboard)  # type: ignore[arg-type]
        token = environment.get("GH_TOKEN")
        if not isinstance(token, str) or not token:
            raise CredentialError("GitHub credentials are unavailable")
        GitHubClient(GitAuth(token, SecretRedactor((token,)))).authenticated_login()
    return dashboard


def _distributions(manifest: BootstrapManifest) -> tuple[DistributionSource, ...]:
    return (manifest.root_distribution, *manifest.profiles)


def _environment_targets(manifest: BootstrapManifest) -> tuple[tuple[str, Path], ...]:
    return (("default", manifest.data_root), *((profile.name, profile.target) for profile in manifest.profiles))


def _private_scratch(data_root: Path) -> PrivateDirectory:
    _require_safe_directory(data_root)
    try:
        return create_private_directory(
            data_root,
            prefix=".hermes-bootstrap-",
        )
    except (OSError, ValueError):
        raise ApplyError("could not create private bootstrap staging") from None


def _cleanup_apply_resources(
    scratch: PrivateDirectory | None,
    results: list[tuple[SharedRepository, RemoteSyncResult]],
    data_root: Path,
) -> bool:
    success = True
    if scratch is not None:
        success = scratch.cleanup() and success
    for repo, result in results:
        tree = result.working_tree
        if tree is None or tree == repo.target or tree == repo.legacy_target:
            continue
        # synchronize_remote only returns a private first-clone outside the canonical target.
        if not repo.target.is_relative_to(data_root):
            success = False
        elif tree.parent == repo.target.parent and tree.name.startswith(".hermes-repository-"):
            if result.private_directory is None:
                success = False
            else:
                success = result.private_directory.cleanup() and success
    return success


def _runtime_token(manifest: BootstrapManifest, environ: Mapping[str, str]) -> str:
    process = environ.get("GH_TOKEN")
    if isinstance(process, str) and process:
        return process
    home = environ.get("HERMES_HOME")
    if isinstance(home, str) and home:
        runtime_home = Path(home)
        if not _safe_runtime_home(manifest.data_root, runtime_home):
            raise CredentialError("GitHub credentials are unavailable")
        token = _read_env_token(runtime_home / ".env")
        if token is not None:
            return token
    token = _read_env_token(manifest.data_root / ".env")
    if token is not None:
        return token
    raise CredentialError("GitHub credentials are unavailable")


def _read_env_token(path: Path) -> str | None:
    try:
        parent_descriptor = open_absolute_directory(path.parent)
    except FileNotFoundError:
        return None
    except (OSError, ValueError):
        raise CredentialError("GitHub credentials are unavailable") from None
    descriptor: int | None = None
    try:
        flags = os.O_RDONLY | os.O_CLOEXEC | os.O_NONBLOCK
        if hasattr(os, "O_NOFOLLOW"):
            flags |= os.O_NOFOLLOW
        try:
            descriptor = os.open(path.name, flags, dir_fd=parent_descriptor)
        except FileNotFoundError:
            return None
        except OSError:
            raise CredentialError("GitHub credentials are unavailable") from None
        try:
            metadata = os.fstat(descriptor)
            if (
                not stat.S_ISREG(metadata.st_mode)
                or metadata.st_nlink != 1
                or metadata.st_size > _ENV_LIMIT
            ):
                raise CredentialError("GitHub credentials are unavailable")
            with os.fdopen(descriptor, "rb") as stream:
                descriptor = None
                data = stream.read(_ENV_LIMIT + 1)
            text = data.decode("utf-8")
        except (OSError, UnicodeError):
            raise CredentialError("GitHub credentials are unavailable") from None
    finally:
        if descriptor is not None:
            os.close(descriptor)
        os.close(parent_descriptor)
    if len(data) > _ENV_LIMIT or "\x00" in text:
        raise CredentialError("GitHub credentials are unavailable")
    token: str | None = None
    for binding in parse_stream(StringIO(text)):
        original = binding.original.string
        first_line = original.split("\n", 1)[0]
        declared = first_line.startswith("GH_TOKEN=")
        if binding.error:
            if declared:
                raise CredentialError("GitHub credentials are unavailable")
            continue
        if binding.key != "GH_TOKEN" or not declared:
            continue
        value = binding.value
        normalized_original = original[:-1] if original.endswith("\n") else original
        if (
            token is not None
            or not isinstance(value, str)
            or not value
            or "\r" in value
            or "\n" in value
            or "\r" in normalized_original
            or "\n" in normalized_original
        ):
            raise CredentialError("GitHub credentials are unavailable")
        token = value
    return token


def _validate_installed_layout(
    manifest: BootstrapManifest, *, allow_active_transaction: bool
) -> dict[str, list[str]]:
    try:
        root = manifest.data_root
        _require_safe_directory(root)
        _require_no_git(root)
        _validate_root_state(manifest)
        _validate_profiles(manifest)
        _validate_repositories(manifest)
        for profile, target in _environment_targets(manifest):
            required = (
                _MANAGED_ENV_KEYS
                if profile == "default"
                else _MANAGED_ENV_KEYS - API_SERVER_KEYS
            )
            _validate_env_file(target / ".env", required)
        if not allow_active_transaction:
            _validate_no_transaction(root)
    except ValidationError:
        raise
    except Exception:
        raise ValidationError("installed Hermes layout is invalid") from None
    return {
        "profiles": [profile.name for profile in manifest.profiles],
        "repositories": [repo.name for repo in manifest.shared_repositories],
    }


def _validate_root_state(manifest: BootstrapManifest) -> None:
    # C5 owns this canonical state filename; no second state format is introduced here.
    state = manifest.data_root / ".bootstrap" / "root-distribution-state.json"
    _require_safe_directory(state.parent)
    raw = _read_json_regular(state)
    if set(raw) != {"source", "ref", "commit", "version", "distribution_owned"}:
        raise ValidationError("installed root distribution state is invalid")
    if raw["source"] != manifest.root_distribution.source or raw["ref"] != manifest.root_distribution.ref:
        raise ValidationError("installed root distribution state is invalid")
    if not all(isinstance(raw[key], str) and raw[key] for key in ("source", "ref", "commit", "version")):
        raise ValidationError("installed root distribution state is invalid")
    if _OBJECT_ID.fullmatch(raw["commit"]) is None or not isinstance(raw["distribution_owned"], list):
        raise ValidationError("installed root distribution state is invalid")
    try:
        owned = _normalize_owned_paths(raw["distribution_owned"], None, require_sources=False)
    except Exception:
        raise ValidationError("installed root distribution state is invalid") from None
    for relative in owned:
        _require_safe_owned_tree(
            manifest.data_root, manifest.data_root.joinpath(*relative.parts)
        )


def _validate_profiles(manifest: BootstrapManifest) -> None:
    directory = manifest.data_root / "profiles"
    _require_safe_directory(directory)
    expected = {profile.name: profile for profile in manifest.profiles}
    for name, profile in expected.items():
        target = directory / name
        _require_safe_directory(target)
        _require_no_git(target)
        try:
            installed, owned = _read_profile_manifest_at(target, name, require_sources=False)
        except Exception:
            raise ValidationError("installed profile distribution is invalid") from None
        if getattr(installed, "source", None) != profile.source:
            raise ValidationError("installed profile distribution is invalid")
        _require_regular_file(target / "distribution.yaml")
        for relative in owned:
            destination = (
                target / ".env.EXAMPLE"
                if relative == PurePosixPath(".env.template")
                else target.joinpath(*relative.parts)
            )
            _require_safe_owned_tree(target, destination)


def _validate_repositories(manifest: BootstrapManifest) -> None:
    for repo in manifest.shared_repositories:
        _require_safe_directory(repo.target)
        git = repo.target / ".git"
        _require_safe_directory(git)
        remote = _git_remote_url(git / "config")
        if remote is None or not _same_remote_identity(repo.source, remote):
            raise ValidationError("installed shared repository is invalid")
        _git_head(git)
        if repo.legacy_target is not None and os.path.lexists(repo.legacy_target):
            raise ValidationError("deprecated shared repository path remains")


def _validate_env_file(path: Path, required: frozenset[str]) -> None:
    try:
        metadata = path.lstat()
        if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode) or stat.S_IMODE(metadata.st_mode) != 0o600:
            raise ValueError
    except (OSError, UnicodeError, ValueError):
        raise ValidationError("installed environment file is invalid") from None
    try:
        values = read_environment_values(
            path, _MANAGED_ENV_KEYS | {_PLAINTEXT_DASHBOARD_PASSWORD}
        )
    except BootstrapError:
        raise ValidationError("installed environment file is invalid") from None
    if set(values) != required:
        raise ValidationError("installed environment file is invalid")
    if any(not values[key].strip() for key in required):
        raise ValidationError("installed environment file is invalid")
    if len({values[key] for key in GITHUB_KEYS}) != 1:
        raise ValidationError("installed environment file is invalid")
    if (
        _SLACK_BOT_TOKEN.fullmatch(values["SLACK_BOT_TOKEN"]) is None
        or _SLACK_APP_TOKEN.fullmatch(values["SLACK_APP_TOKEN"]) is None
    ):
        raise ValidationError("installed environment file is invalid")
    if not _is_reusable_signing_secret(
        values.get("HERMES_DASHBOARD_BASIC_AUTH_SECRET")
    ):
        raise ValidationError("installed environment file is invalid")
    if "API_SERVER_KEY" in required and not _is_reusable_api_server_key(
        values.get("API_SERVER_KEY")
    ):
        raise ValidationError("installed environment file is invalid")


def _validate_no_transaction(root: Path) -> None:
    store = root / ".bootstrap" / "transactions"
    if not os.path.lexists(store):
        return
    _require_safe_directory(store)
    entries = list(store.iterdir())
    if any(entry.name != ".lock" for entry in entries):
        raise ValidationError("an incomplete bootstrap transaction remains")
    if not entries:
        return
    try:
        metadata = entries[0].lstat()
    except OSError:
        raise ValidationError("bootstrap transaction lock is invalid") from None
    if (
        stat.S_ISLNK(metadata.st_mode)
        or not stat.S_ISREG(metadata.st_mode)
        or metadata.st_nlink != 1
        or stat.S_IMODE(metadata.st_mode) != 0o600
    ):
        raise ValidationError("bootstrap transaction lock is invalid")


def _read_json_regular(path: Path) -> dict[str, object]:
    _require_regular_file(path)
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, ValueError):
        raise ValidationError("installed root distribution state is invalid") from None
    if not isinstance(value, dict) or any(not isinstance(key, str) for key in value):
        raise ValidationError("installed root distribution state is invalid")
    return value


def _require_safe_owned_tree(owner_root: Path, path: Path) -> None:
    try:
        relative = path.relative_to(owner_root)
    except ValueError:
        raise ValidationError("installed distribution target is invalid") from None
    current = owner_root
    for component in relative.parts[:-1]:
        current = current / component
        try:
            metadata = current.lstat()
        except OSError:
            raise ValidationError("installed distribution target is invalid") from None
        if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
            raise ValidationError("installed distribution target is invalid")

    inode_counts: dict[tuple[int, int], int] = {}
    inode_links: dict[tuple[int, int], int] = {}

    def walk(current: Path) -> None:
        try:
            metadata = current.lstat()
        except OSError:
            raise ValidationError("installed distribution target is invalid") from None
        if stat.S_ISLNK(metadata.st_mode):
            raise ValidationError("installed distribution target is invalid")
        if stat.S_ISREG(metadata.st_mode):
            identity = (metadata.st_dev, metadata.st_ino)
            inode_counts[identity] = inode_counts.get(identity, 0) + 1
            inode_links[identity] = metadata.st_nlink
            return
        if not stat.S_ISDIR(metadata.st_mode):
            raise ValidationError("installed distribution target is invalid")
        try:
            entries = tuple(Path(entry.path) for entry in os.scandir(current))
        except OSError:
            raise ValidationError("installed distribution target is invalid") from None
        for entry in entries:
            walk(entry)

    walk(path)
    if any(inode_counts[identity] != links for identity, links in inode_links.items()):
        raise ValidationError("installed distribution target is invalid")


def _require_no_git(path: Path) -> None:
    if (path / ".git").exists() or (path / ".git").is_symlink():
        raise ValidationError("installed data root is invalid")


def _require_safe_directory(path: Path) -> None:
    if not _safe_absolute_directory(path):
        raise ValidationError("installed Hermes layout is invalid")


def _safe_absolute_directory(path: Path) -> bool:
    if not path.is_absolute():
        return False
    current = path
    while True:
        try:
            metadata = current.lstat()
        except OSError:
            return False
        if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
            return False
        if current.parent == current:
            return True
        current = current.parent


def _safe_runtime_home(data_root: Path, candidate: Path) -> bool:
    if not candidate.is_absolute() or not data_root.is_absolute():
        return False
    normalized = Path(os.path.normpath(candidate))
    if candidate != normalized or not normalized.is_relative_to(data_root):
        return False
    if not _safe_absolute_directory(data_root):
        return False
    current = data_root
    for component in normalized.relative_to(data_root).parts:
        current = current / component
        try:
            metadata = current.lstat()
        except OSError:
            return False
        if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
            return False
    return True


def _require_regular_file(path: Path) -> None:
    try:
        metadata = path.lstat()
    except OSError:
        raise ValidationError("installed Hermes layout is invalid") from None
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1:
        raise ValidationError("installed Hermes layout is invalid")


def _source_identity(source: str) -> tuple[str, str] | None:
    identity = _remote_identity(source)
    if identity is None or identity[0] != "https":
        return None
    parts = identity[2].strip("/").split("/")
    if len(parts) != 2 or not all(parts):
        return None
    return (parts[0], parts[1])


def _git_remote_url(config: Path) -> str | None:
    _require_regular_file(config)
    section = ""
    url: str | None = None
    origin_sections = 0
    try:
        for line in config.read_text(encoding="utf-8").splitlines():
            stripped = line.strip()
            if stripped.startswith("[") and stripped.endswith("]"):
                section = stripped
                if section.casefold().startswith("[include"):
                    raise ValueError
                if section == '[remote "origin"]':
                    origin_sections += 1
                    if origin_sections != 1:
                        raise ValueError
            elif section == '[remote "origin"]' and "=" in stripped:
                key, value = stripped.split("=", 1)
                if key.strip().casefold() == "url":
                    if url is not None or not value.strip():
                        raise ValueError
                    url = value.strip()
    except (OSError, UnicodeError, ValueError):
        raise ValidationError("installed shared repository is invalid") from None
    return url if origin_sections == 1 else None


def _git_head(git: Path) -> str:
    _require_safe_directory(git)
    _require_regular_file(git / "HEAD")
    try:
        head = (git / "HEAD").read_text(encoding="ascii").strip()
        if head.startswith("ref: "):
            ref = head[5:]
            head = _read_git_symbolic_ref(git, ref)
    except (OSError, UnicodeError, ValueError):
        raise ValidationError("installed shared repository is invalid") from None
    if _OBJECT_ID.fullmatch(head) is None:
        raise ValidationError("installed shared repository is invalid")
    return head


def _read_git_symbolic_ref(git: Path, ref: str) -> str:
    components = ref.split("/")
    if (
        len(components) < 2
        or components[0] != "refs"
        or "\\" in ref
        or any(component in {"", ".", ".."} for component in components)
        or any(component.startswith(".") or component.endswith(".lock") for component in components)
        or "@{" in ref
        or any(character in ref for character in " ~^:?*[")
        or any(ord(character) < 32 or ord(character) == 127 for character in ref)
    ):
        raise ValueError("invalid symbolic Git ref")

    current = git
    for component in components[:-1]:
        current = current / component
        metadata = current.lstat()
        if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
            raise ValueError("unsafe symbolic Git ref")
    target = current / components[-1]
    _require_regular_file(target)
    return target.read_text(encoding="ascii").strip()
