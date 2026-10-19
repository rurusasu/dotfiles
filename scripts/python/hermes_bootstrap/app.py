"""Hermes bootstrap command orchestration and installed-layout validation."""

from __future__ import annotations

import json
import os
import re
import stat
import tempfile
from collections.abc import Mapping
from pathlib import Path, PurePosixPath
from typing import TextIO

from . import onepassword, profile_sync
from .configfiles import (
    reconcile_onepassword_cli_permissions,
    reconcile_onepassword_configurations,
    reconcile_chrome_configurations,
    reconcile_xapi_configurations,
    validate_chrome_configurations,
    validate_onepassword_configurations,
    validate_xapi_configurations,
)
from .context_engine import (
    install_context_engine_configurations,
    validate_context_engine_installation,
)
from .distributions import (
    _normalize_owned_paths,
    _read_profile_manifest_at,
    apply_profile_distribution,
    apply_root_distribution,
)
from .engine_lock import EngineLock
from .errors import (
    ApplyError,
    BootstrapError,
    CredentialError,
    RepositoryError,
    ValidationError,
)
from .filesystem import (
    PrivateDirectory,
    create_private_directory,
)
from .git import (
    _git_environment,
    _run_git,
    _same_remote_identity,
    stage_distribution,
)
from .google_calendar import (
    install_google_calendar_configurations,
    install_google_calendar_credentials,
    validate_google_calendar_installation,
)
from .google_gmail import (
    install_google_gmail_configurations,
    install_google_gmail_credentials,
    validate_google_gmail_installation,
)
from .github import GitAuth
from .manifest import load_manifest
from .models import BootstrapManifest, DistributionSource, SharedRepository
from .payload import build_secret_plan, read_secret_payload
from .profile_sync import ProfileSyncReport
from .repositories import (
    RemoteSyncResult,
    apply_shared_working_tree,
    synchronize_named_repository,
    synchronize_remote,
)
from .source_contracts import validate_chrome_mcp_sources


_OBJECT_ID = re.compile(r"[0-9a-f]{40}(?:[0-9a-f]{24})?\Z")


def secret_plan(manifest_path: Path) -> dict[str, object]:
    """Return the deterministic non-secret adapter plan."""

    return build_secret_plan(load_manifest(manifest_path))


def apply(manifest_path: Path, input_stream: TextIO) -> dict[str, object]:
    """Apply the staged bootstrap inputs without printing secrets."""

    manifest = load_manifest(manifest_path)
    with EngineLock.acquire(manifest.data_root) as engine_lock:
        engine_lock.require_held()
        return _apply(manifest, input_stream)


def _apply(manifest: BootstrapManifest, input_stream: TextIO) -> dict[str, object]:
    scratch: PrivateDirectory | None = None
    remote_results: list[tuple[SharedRepository, RemoteSyncResult]] = []
    try:
        secrets = read_secret_payload(input_stream, manifest)
        auth = GitAuth(secrets.github_token)

        scratch = _private_scratch(manifest.data_root)
        profile_sources = _missing_profiles(manifest)
        missing_names = {source.name for source in profile_sources}
        profile_sync_summary = {
            source.name: "installed" if source.name in missing_names else "preserved"
            for source in manifest.profiles
        }

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

        reconcile_onepassword_cli_permissions(manifest.data_root)
        apply_root_distribution(root_stage, manifest.data_root)
        for stage in profile_stages:
            apply_profile_distribution(
                stage,
                manifest.data_root,
            )
        for repo, result in remote_results:
            apply_shared_working_tree(repo, result)

        install_google_calendar_configurations(
            [target for _profile, target in _environment_targets(manifest)],
        )
        install_google_gmail_configurations(
            [target for _profile, target in _environment_targets(manifest)],
        )
        install_context_engine_configurations(_environment_targets(manifest))
        runtime_targets = _runtime_config_targets(manifest)
        reconcile_chrome_configurations(runtime_targets)
        reconcile_xapi_configurations(runtime_targets)
        install_google_calendar_credentials(
            manifest.data_root,
            secrets.google_calendar,
        )
        install_google_gmail_credentials(
            manifest.data_root,
            secrets.google_calendar,
        )

        reconcile_onepassword_configurations(
            manifest,
            _environment_targets(manifest),
        )

        _validate_installed_layout(manifest)
        return {
            "status": "applied",
            "profiles": [profile.name for profile in manifest.profiles],
            "repositories": [repo.name for repo in manifest.shared_repositories],
            "profile_sync": profile_sync_summary,
        }
    except BootstrapError:
        raise
    except Exception:
        raise ApplyError("bootstrap apply failed") from None
    finally:
        if not _cleanup_apply_resources(scratch, remote_results, manifest.data_root):
            raise ApplyError("could not clean bootstrap staging resources") from None


def validate(manifest_path: Path) -> dict[str, object]:
    """Validate the installed runtime without network or mutation."""

    manifest = load_manifest(manifest_path)
    result = _validate_installed_layout(manifest)
    return {"status": "valid", **result}


def sync_repository(
    manifest_path: Path, name: str, environ: Mapping[str, str] | None = None
) -> dict[str, object]:
    """Synchronize a declared canonical checkout using a runtime token."""

    manifest = load_manifest(manifest_path)
    environment = os.environ if environ is None else environ
    try:
        with EngineLock.acquire(manifest.data_root) as engine_lock:
            engine_lock.require_held()
            token = _runtime_token(manifest, environment)
            auth = GitAuth(token)
            result = synchronize_named_repository(name, manifest, auth)
            return {"status": "synchronized", "name": result.name, "commit": result.commit, "pushed": result.pushed}
    except BootstrapError:
        raise
    except Exception:
        raise CredentialError("GitHub credentials are unavailable") from None


def sync_profiles(
    manifest_path: Path,
    *,
    dry_run: bool,
    environ: Mapping[str, str] | None = None,
) -> ProfileSyncReport:
    """Synchronize every configured local profile using a runtime token."""

    manifest = load_manifest(manifest_path)
    environment = os.environ if environ is None else environ
    try:
        with EngineLock.acquire(manifest.data_root) as engine_lock:
            engine_lock.require_held()
            token = _runtime_token(manifest, environment)
            auth = GitAuth(token)
            return profile_sync.synchronize_profiles(manifest, auth, dry_run=dry_run)
    except CredentialError:
        return profile_sync.failed_profile_report(
            manifest.profiles,
            dry_run=dry_run,
            category="credentials_unavailable",
            message="GitHub credentials are unavailable",
            exit_code=CredentialError.exit_code,
        )
    except Exception:
        return profile_sync.failed_profile_report(
            manifest.profiles,
            dry_run=dry_run,
            category="repository",
            message="profile synchronization failed",
            exit_code=RepositoryError.exit_code,
        )


def _missing_profiles(manifest: BootstrapManifest) -> tuple[DistributionSource, ...]:
    """Validate installed profiles and identify absent installation targets."""

    missing: list[DistributionSource] = []
    try:
        for profile in manifest.profiles:
            if profile.target != manifest.data_root / "profiles" / profile.name:
                raise ValidationError("installed profile distribution is invalid")
            for directory in (*reversed(profile.target.parents), profile.target):
                try:
                    metadata = directory.lstat()
                except FileNotFoundError:
                    missing.append(profile)
                    break
                if not stat.S_ISDIR(metadata.st_mode):
                    raise ValidationError("installed profile distribution is invalid")
            else:
                _validate_profile(profile)
    except (OSError, ValidationError):
        raise RepositoryError("installed profile distribution is invalid") from None
    return tuple(missing)


def _environment_targets(manifest: BootstrapManifest) -> tuple[tuple[str, Path], ...]:
    return (("default", manifest.data_root), *((profile.name, profile.target) for profile in manifest.profiles))


def _runtime_config_targets(manifest: BootstrapManifest) -> list[Path]:
    """Return every managed or locally created runtime profile."""

    targets: list[Path] = []
    for _profile, target in _environment_targets(manifest):
        try:
            (target / "config.yaml").lstat()
        except FileNotFoundError:
            continue
        except OSError:
            raise ApplyError("could not inspect Hermes runtime profiles") from None
        targets.append(target)
    managed = set(targets)
    directory = manifest.data_root / "profiles"
    try:
        entries = sorted(directory.iterdir(), key=lambda entry: entry.name)
    except FileNotFoundError:
        return targets
    except OSError:
        raise ApplyError("could not inspect Hermes runtime profiles") from None
    for entry in entries:
        if entry in managed:
            continue
        try:
            directory_metadata = entry.lstat()
        except OSError:
            raise ApplyError("could not inspect Hermes runtime profiles") from None
        if stat.S_ISLNK(directory_metadata.st_mode):
            raise ApplyError("could not inspect Hermes runtime profiles")
        if not stat.S_ISDIR(directory_metadata.st_mode):
            continue
        try:
            (entry / "config.yaml").lstat()
        except FileNotFoundError:
            continue
        except OSError:
            raise ApplyError("could not inspect Hermes runtime profiles") from None
        targets.append(entry)
    return targets


def _private_scratch(data_root: Path) -> PrivateDirectory:
    _require_safe_directory(data_root)
    try:
        return create_private_directory(
            Path(tempfile.gettempdir()),
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
        if tree is None or tree == repo.target:
            continue
        # synchronize_remote only returns a private first-clone outside the canonical target.
        if not repo.target.is_relative_to(data_root):
            success = False
        elif tree.parent == repo.target.parent and tree.name.startswith(".hermes-repository-"):
            if result.private_directory is None:
                success = False
            else:
                owner = result.private_directory
                success = owner.cleanup() and success
    return success


def _runtime_token(manifest: BootstrapManifest, environ: Mapping[str, str]) -> str:
    for name in ("GH_TOKEN", "GITHUB_TOKEN", "GITHUB_PERSONAL_ACCESS_TOKEN"):
        token = environ.get(name)
        if isinstance(token, str) and token:
            return token
    return onepassword.read_github_token(manifest, environ)


def _validate_installed_layout(manifest: BootstrapManifest) -> dict[str, list[str]]:
    try:
        root = manifest.data_root
        _require_safe_directory(root)
        _require_no_git(root)
        _validate_root_state(manifest)
        _validate_profiles(manifest)
        _validate_repositories(manifest)
        validate_google_calendar_installation(
            manifest.data_root,
            [target for _profile, target in _environment_targets(manifest)],
        )
        validate_google_gmail_installation(
            manifest.data_root,
            [target for _profile, target in _environment_targets(manifest)],
        )
        runtime_targets = _runtime_config_targets(manifest)
        validate_xapi_configurations(runtime_targets)
        validate_chrome_configurations(runtime_targets)
        validate_context_engine_installation(_environment_targets(manifest))
        validate_onepassword_configurations(
            manifest, _environment_targets(manifest)
        )
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
    for profile in manifest.profiles:
        _validate_profile(profile)


def _validate_profile(profile: DistributionSource) -> None:
    target = profile.target
    _require_safe_directory(target)
    _require_no_git(target)
    try:
        installed, owned = _read_profile_manifest_at(target, profile.name, require_sources=False)
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
    environment = _git_environment(GitAuth("local-validation"), Path(os.devnull))
    environment["GIT_NO_LAZY_FETCH"] = "1"
    for repo in manifest.shared_repositories:
        _require_safe_directory(repo.target)
        git = repo.target / ".git"
        _require_safe_directory(git)
        _require_regular_file(git / "config")
        _require_regular_file(git / "HEAD")
        _require_safe_directory(git / "objects")
        _require_safe_owned_tree(repo.target, git)
        remote = _run_git(
            ("config", "--local", "--no-includes", "--get-all", "remote.origin.url"),
            repo.target,
            environment,
        )
        head = _run_git(("rev-parse", "--verify", "HEAD^{commit}"), repo.target, environment)
        if (
            remote is None
            or not _same_remote_identity(repo.source, remote)
            or head is None
            or _OBJECT_ID.fullmatch(head) is None
        ):
            raise ValidationError("installed shared repository is invalid")


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

    def walk(current: Path) -> None:
        try:
            metadata = current.lstat()
        except OSError:
            raise ValidationError("installed distribution target is invalid") from None
        if stat.S_ISLNK(metadata.st_mode):
            raise ValidationError("installed distribution target is invalid")
        if stat.S_ISREG(metadata.st_mode):
            if metadata.st_nlink != 1:
                raise ValidationError("installed distribution target is invalid")
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


def _require_regular_file(path: Path) -> None:
    try:
        metadata = path.lstat()
    except OSError:
        raise ValidationError("installed Hermes layout is invalid") from None
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1:
        raise ValidationError("installed Hermes layout is invalid")
