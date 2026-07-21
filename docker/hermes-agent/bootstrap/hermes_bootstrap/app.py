"""Hermes bootstrap command orchestration and installed-layout validation."""

from __future__ import annotations

import json
import os
import re
import shutil
import stat
import tempfile
from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Callable, TextIO

from .distributions import (
    _normalize_owned_paths,
    _read_profile_manifest_at,
    apply_profile_distribution,
    apply_root_distribution,
)
from .envfiles import (
    DASHBOARD_KEYS,
    GITHUB_KEYS,
    SLACK_KEYS,
    build_dashboard_environment,
    build_profile_environment,
    merge_env_file,
)
from .errors import ApplyError, BootstrapError, CredentialError, RollbackError, ValidationError
from .git import _remote_identity, _same_remote_identity, stage_distribution
from .github import GitAuth, GitHubClient
from .manifest import load_manifest
from .models import BootstrapManifest, DistributionSource, SharedRepository
from .payload import SecretRedactor, build_secret_plan, read_secret_payload
from .repositories import (
    RemoteSyncResult,
    apply_shared_working_tree,
    synchronize_named_repository,
    synchronize_remote,
)
from .transaction import Transaction


_ENV_LIMIT = 1024 * 1024
_OBJECT_ID = re.compile(r"[0-9a-f]{40}(?:[0-9a-f]{24})?\Z")
_ENV_ASSIGNMENT = re.compile(r"(?:export[ \t]+)?([A-Za-z_][A-Za-z0-9_]*)[ \t]*=")
_MANAGED_ENV_KEYS = GITHUB_KEYS | DASHBOARD_KEYS | SLACK_KEYS
_PLAINTEXT_DASHBOARD_PASSWORD = "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD"
_failpoint: Callable[[str], None] = lambda _name: None


@dataclass(frozen=True)
class _ApplyOutcome:
    result: dict[str, object] | None = None
    error_type: type[BootstrapError] | None = None
    message: str | None = None


def secret_plan(manifest_path: Path) -> dict[str, object]:
    """Return the deterministic non-secret adapter plan."""

    return build_secret_plan(load_manifest(manifest_path))


def apply(manifest_path: Path, input_stream: TextIO) -> dict[str, object]:
    """Perform one fully staged bootstrap transaction without printing secrets."""

    manifest = load_manifest(manifest_path)
    Transaction.recover_if_needed(manifest.data_root)
    outcome = _apply_sensitive_boundary(manifest_path, manifest, input_stream)
    del input_stream
    if outcome.error_type is not None:
        error_type = outcome.error_type
        message = outcome.message or "bootstrap apply failed"
        del outcome
        raise error_type(message) from None
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
        outcome = _ApplyOutcome(error_type=type(error), message=str(error))
        del error
        return outcome
    except Exception:
        return _ApplyOutcome(error_type=ApplyError, message="bootstrap apply failed")


def _apply_sensitive(
    manifest_path: Path, manifest: BootstrapManifest, input_stream: TextIO
) -> dict[str, object]:
    """Own all secret-bearing values behind the non-raising boundary."""

    scratch: Path | None = None
    remote_results: list[tuple[SharedRepository, RemoteSyncResult]] = []
    tx: Transaction | None = None
    primary: BootstrapError | None = None
    rollback_error: RollbackError | None = None
    result: dict[str, object] | None = None
    try:
        secrets = read_secret_payload(input_stream, manifest)
        auth = GitAuth(secrets.github_token, secrets.redactor)
        _validate_remote_credentials(manifest, auth)
        _validate_profile_credentials(manifest, secrets)

        scratch = _private_scratch(manifest.data_root)
        staged = [stage_distribution(source, scratch, auth) for source in _distributions(manifest)]
        for repo in manifest.shared_repositories:
            remote_results.append((repo, synchronize_remote(repo, auth)))

        tx = Transaction.begin(manifest.data_root)
        root_stage = staged[0]
        apply_root_distribution(root_stage, manifest.data_root, tx)
        _failpoint("root-apply")
        for stage in staged[1:]:
            apply_profile_distribution(stage, manifest.data_root, tx)
            _failpoint(f"profile-apply:{stage.declaration.name}")
        for repo, result in remote_results:
            apply_shared_working_tree(repo, result, tx)
            _failpoint(f"shared-apply:{repo.name}")

        dashboard = build_dashboard_environment(secrets)
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
        }
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
        raise rollback_error
    if cleanup_failed:
        raise ApplyError("could not clean bootstrap staging resources")
    if primary is not None:
        raise primary
    if result is None:
        raise ApplyError("bootstrap apply failed")
    return result


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


def _sync_repository_boundary(
    manifest: BootstrapManifest, name: str, environ: Mapping[str, str]
) -> dict[str, object]:
    token: str | None = None
    try:
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


def _validate_profile_credentials(manifest: BootstrapManifest, secrets: object) -> None:
    """Exercise the credentials that each resulting profile will receive."""

    dashboard = build_dashboard_environment(secrets)  # type: ignore[arg-type]
    try:
        for profile, _target in _environment_targets(manifest):
            environment = build_profile_environment(profile, secrets, dashboard)  # type: ignore[arg-type]
            token = environment.get("GH_TOKEN")
            if not isinstance(token, str) or not token:
                raise CredentialError("GitHub credentials are unavailable")
            GitHubClient(GitAuth(token, SecretRedactor((token,)))).authenticated_login()
    finally:
        del dashboard


def _distributions(manifest: BootstrapManifest) -> tuple[DistributionSource, ...]:
    return (manifest.root_distribution, *manifest.profiles)


def _environment_targets(manifest: BootstrapManifest) -> tuple[tuple[str, Path], ...]:
    return (("default", manifest.data_root), *((profile.name, profile.target) for profile in manifest.profiles))


def _private_scratch(data_root: Path) -> Path:
    _require_safe_directory(data_root)
    try:
        scratch = Path(tempfile.mkdtemp(prefix=".hermes-bootstrap-", dir=data_root))
        os.chmod(scratch, 0o700)
    except OSError:
        raise ApplyError("could not create private bootstrap staging") from None
    if not _is_private_directory(scratch):
        _remove_tree(scratch)
        raise ApplyError("could not create private bootstrap staging")
    return scratch


def _cleanup_apply_resources(
    scratch: Path | None,
    results: list[tuple[SharedRepository, RemoteSyncResult]],
    data_root: Path,
) -> bool:
    success = True
    if scratch is not None:
        success = _remove_tree(scratch) and success
    for repo, result in results:
        tree = result.working_tree
        if tree is None or tree == repo.target or tree == repo.legacy_target:
            continue
        # synchronize_remote only returns a private first-clone outside the canonical target.
        if not repo.target.is_relative_to(data_root):
            success = False
        elif tree.parent == repo.target.parent and tree.name.startswith(".hermes-repository-"):
            success = _remove_tree(tree) and success
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
        metadata = path.lstat()
    except FileNotFoundError:
        return None
    except OSError:
        raise CredentialError("GitHub credentials are unavailable") from None
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode) or metadata.st_size > _ENV_LIMIT:
        raise CredentialError("GitHub credentials are unavailable")
    try:
        data = path.read_bytes()
        text = data.decode("utf-8")
    except (OSError, UnicodeError):
        raise CredentialError("GitHub credentials are unavailable") from None
    if len(data) > _ENV_LIMIT or "\x00" in text:
        raise CredentialError("GitHub credentials are unavailable")
    token: str | None = None
    for line in text.splitlines():
        if not line.startswith("GH_TOKEN="):
            continue
        value = line[len("GH_TOKEN=") :]
        if token is not None or not value or "\r" in value or "\n" in value:
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
        for _profile, target in _environment_targets(manifest):
            _validate_env_file(target / ".env")
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
    actual = {entry.name for entry in directory.iterdir()}
    if actual != set(expected):
        raise ValidationError("installed profile set is invalid")
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
        if repo.legacy_target is not None:
            if not repo.legacy_target.is_symlink():
                raise ValidationError("shared repository compatibility link is invalid")
            expected = os.path.relpath(repo.target, repo.legacy_target.parent)
            if os.readlink(repo.legacy_target) != expected:
                raise ValidationError("shared repository compatibility link is invalid")


def _validate_env_file(path: Path) -> None:
    try:
        metadata = path.lstat()
        if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode) or stat.S_IMODE(metadata.st_mode) != 0o600:
            raise ValueError
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeError, ValueError):
        raise ValidationError("installed environment file is invalid") from None
    seen: set[str] = set()
    for line in text.splitlines():
        match = _ENV_ASSIGNMENT.match(line)
        if match is None:
            continue
        key = match.group(1)
        if key in _MANAGED_ENV_KEYS:
            if key in seen:
                raise ValidationError("installed environment file is invalid")
            seen.add(key)
        if key == _PLAINTEXT_DASHBOARD_PASSWORD:
            raise ValidationError("installed environment file is invalid")
    if seen != _MANAGED_ENV_KEYS:
        raise ValidationError("installed environment file is invalid")


def _validate_no_transaction(root: Path) -> None:
    store = root / ".bootstrap" / "transactions"
    if not os.path.lexists(store):
        return
    _require_safe_directory(store)
    if any(entry.name != ".lock" for entry in store.iterdir()):
        raise ValidationError("an incomplete bootstrap transaction remains")


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


def _is_private_directory(path: Path) -> bool:
    try:
        metadata = path.lstat()
    except OSError:
        return False
    return stat.S_ISDIR(metadata.st_mode) and not stat.S_ISLNK(metadata.st_mode) and stat.S_IMODE(metadata.st_mode) == 0o700


def _remove_tree(path: Path) -> bool:
    try:
        if path.exists() or path.is_symlink():
            shutil.rmtree(path)
    except OSError:
        return False
    return True


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
