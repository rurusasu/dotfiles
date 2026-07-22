"""Apply Hermes root and named-profile distribution snapshots safely."""

from __future__ import annotations

import json
import os
import re
import shutil
import stat
import tempfile
from dataclasses import dataclass
from pathlib import Path, PurePosixPath, PureWindowsPath
from typing import Any, Protocol

import yaml
from hermes_cli import __version__ as HERMES_VERSION
from hermes_cli import profile_distribution

from .errors import ApplyError
from .git import StagedSource


_ROOT_MANIFEST = "root-distribution.yaml"
_ROOT_STATE = PurePosixPath(".bootstrap/root-distribution-state.json")
_ROOT_KEYS = frozenset({"schema_version", "name", "version", "description", "hermes_requires", "distribution_owned"})
_ROOT_REQUIRED_KEYS = frozenset({"schema_version", "name", "version", "hermes_requires", "distribution_owned"})
_BOOTSTRAP_USER_DIRS = ("memories", "sessions", "skills", "skins", "logs", "plans", "workspace", "cron", "home")
_GITHUB_HTTPS_SOURCE = re.compile(
    r"https://github\.com/[A-Za-z0-9](?:[A-Za-z0-9_.-]*[A-Za-z0-9])?"
    r"/[A-Za-z0-9](?:[A-Za-z0-9_.-]*[A-Za-z0-9])?\.git\Z"
)
_LOWERCASE_OBJECT_ID = re.compile(r"[0-9a-f]{40}(?:[0-9a-f]{24})?\Z")
_RESERVED_TOP_LEVEL = frozenset(
    {
        ".bootstrap",
        ".browser",
        ".env",
        ".git",
        "core",
        "locks",
        "logs",
        "memories",
        "profiles",
        "sessions",
        "shared",
    }
)
_RESERVED_ANYWHERE = frozenset(
    {
        "auth",
        "auth.json",
        "browser",
        "browser_data",
        "cache",
        "caches",
        "credential",
        "credentials",
        "oauth",
        "token",
        "tokens",
    }
)
_RUNTIME_DATABASES = frozenset(
    {
        "hermes_state.db",
        "response_store.db",
        "response_store.db-shm",
        "response_store.db-wal",
        "state.db",
        "state.db-shm",
        "state.db-wal",
    }
)
_ROOT_RESERVED_TOP_LEVEL = _RESERVED_TOP_LEVEL | frozenset(
    name.lower() for name in profile_distribution.USER_OWNED_EXCLUDE
)
_PROFILE_RESERVED_TOP_LEVEL = frozenset(name.lower() for name in profile_distribution.USER_OWNED_EXCLUDE)


class Transaction(Protocol):
    def snapshot(self, path: Path) -> None: ...


class _SnapshotTracker:
    """Apply-local transaction snapshot coverage with ancestor awareness."""

    def __init__(self, tx: Transaction) -> None:
        self._tx = tx
        self.paths: list[Path] = []

    def snapshot(self, path: Path) -> bool:
        for existing in self.paths:
            if path == existing or path.is_relative_to(existing):
                return False
            if existing.is_relative_to(path):
                raise ValueError("snapshot parent follows child")
        self._tx.snapshot(path)
        self.paths.append(path)
        return True


@dataclass(frozen=True)
class ChangeSet:
    """A stable list of runtime paths potentially changed by an apply."""

    changed_paths: tuple[Path, ...]

    def __post_init__(self) -> None:
        object.__setattr__(
            self,
            "changed_paths",
            tuple(sorted(set(self.changed_paths), key=lambda path: path.as_posix())),
        )


@dataclass(frozen=True)
class RootDistributionManifest:
    schema_version: int
    name: str
    version: str
    hermes_requires: str
    distribution_owned: tuple[PurePosixPath, ...]


@dataclass(frozen=True)
class _Failure:
    message: str


class _UniqueKeyLoader(yaml.SafeLoader):
    pass


def _construct_mapping(loader: yaml.SafeLoader, node: yaml.nodes.MappingNode, deep: bool = False) -> dict[object, object]:
    mapping: dict[object, object] = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in mapping:
            raise ValueError("duplicate mapping key")
        mapping[key] = loader.construct_object(value_node, deep=deep)
    return mapping


_UniqueKeyLoader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, _construct_mapping)


def load_root_manifest(stage: Path) -> RootDistributionManifest:
    """Load a strictly-defined root distribution manifest without leaking its path."""

    result = _load_root_manifest_boundary(stage)
    if isinstance(result, _Failure):
        message = result.message
        del result
        del stage
        raise ApplyError(message)
    return result


def apply_root_distribution(stage: StagedSource, data_root: Path, tx: Transaction) -> ChangeSet:
    """Replace only root-owned paths and persist canonical ownership state."""

    result = _apply_root_boundary(stage, data_root, tx)
    if isinstance(result, _Failure):
        message = result.message
        del result
        del stage
        del data_root
        del tx
        raise ApplyError(message)
    return result


def build_sanitized_profile_source(stage: StagedSource, scratch_root: Path) -> Path:
    """Build a private source payload containing only a profile manifest and owned paths."""

    result = _build_sanitized_boundary(stage, scratch_root)
    if isinstance(result, _Failure):
        message = result.message
        del result
        del stage
        del scratch_root
        raise ApplyError(message)
    return result


def apply_profile_distribution(stage: StagedSource, data_root: Path, tx: Transaction) -> ChangeSet:
    """Install one staged profile through Hermes' supported distribution API."""

    result = _apply_profile_boundary(stage, data_root, tx)
    if isinstance(result, _Failure):
        message = result.message
        del result
        del stage
        del data_root
        del tx
        raise ApplyError(message)
    return result


def _load_root_manifest_boundary(stage: Path) -> RootDistributionManifest | _Failure:
    try:
        return _read_root_manifest(stage)
    except Exception:
        return _Failure("could not load the root distribution manifest")


def _read_root_manifest(stage: Path) -> RootDistributionManifest:
    _require_regular_file(stage / _ROOT_MANIFEST)
    raw = yaml.load((stage / _ROOT_MANIFEST).read_text(encoding="utf-8"), Loader=_UniqueKeyLoader)
    if not isinstance(raw, dict) or any(not isinstance(key, str) for key in raw):
        raise ValueError("root manifest must be a mapping")
    keys = frozenset(raw)
    if not _ROOT_REQUIRED_KEYS <= keys or not keys <= _ROOT_KEYS:
        raise ValueError("root manifest has unsupported keys")
    schema_version = raw["schema_version"]
    name = raw["name"]
    version = raw["version"]
    hermes_requires = raw["hermes_requires"]
    owned = raw["distribution_owned"]
    if (
        type(schema_version) is not int
        or schema_version != 1
        or not isinstance(name, str)
        or name != "default"
        or not isinstance(version, str)
        or not version.strip()
        or version != version.strip()
        or not isinstance(hermes_requires, str)
        or not hermes_requires
        or hermes_requires != hermes_requires.strip()
        or not isinstance(owned, list)
        or any(not isinstance(item, str) for item in owned)
        or ("description" in raw and not isinstance(raw["description"], str))
    ):
        raise ValueError("root manifest has invalid values")
    profile_distribution.check_hermes_requires(hermes_requires, HERMES_VERSION)
    normalized = _normalize_owned_paths(owned, stage, require_sources=True)
    return RootDistributionManifest(schema_version, name, version, hermes_requires, normalized)


def _apply_root_boundary(stage: StagedSource, data_root: Path, tx: Transaction) -> ChangeSet | _Failure:
    try:
        _require_data_root(data_root)
        if stage.declaration.name != "default" or stage.declaration.target != data_root:
            raise ValueError("invalid root declaration")
        manifest = _read_root_manifest(stage.path)
        snapshots = _SnapshotTracker(tx)
        state_path = data_root.joinpath(*_ROOT_STATE.parts)
        prior_owned = _read_prior_root_state(state_path)
        next_owned = manifest.distribution_owned
        changed: list[Path] = []
        stale_owned = tuple(
            owned
            for owned in prior_owned
            if not any(owned.is_relative_to(candidate) for candidate in next_owned)
        )
        replacement_stale = tuple(
            owned for owned in stale_owned if any(candidate.is_relative_to(owned) for candidate in next_owned)
        )
        deferred_stale = tuple(owned for owned in stale_owned if owned not in replacement_stale)
        for owned in sorted(replacement_stale, key=lambda path: (len(path.parts), path.as_posix())):
            destination = data_root.joinpath(*owned.parts)
            _require_safe_managed_path(data_root, destination)
            if _lexists(destination):
                _snapshot(snapshots, destination)
                _remove_destination(destination)
                changed.append(destination)
        next_set = set(next_owned)
        for owned in sorted((*next_owned, *deferred_stale), key=lambda path: path.as_posix()):
            destination = data_root.joinpath(*owned.parts)
            _require_safe_managed_path(data_root, destination)
            if owned in next_set:
                source = stage.path.joinpath(*owned.parts)
                if _same_path(source, destination):
                    continue
                _ensure_destination_parent(destination.parent, snapshots)
                _snapshot(snapshots, destination)
                _replace_from_source(source, destination, snapshots)
                changed.append(destination)
            elif _lexists(destination):
                _snapshot(snapshots, destination)
                _remove_destination(destination)
                changed.append(destination)
        state = _canonical_state(stage, manifest)
        state_bytes = (json.dumps(state, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")
        _require_safe_managed_path(data_root, state_path)
        if not _same_regular_bytes(state_path, state_bytes):
            _ensure_state_parent(data_root, state_path.parent, snapshots)
            _require_safe_destination(data_root, state_path.parent)
            _snapshot(snapshots, state_path)
            _atomic_write(state_path, state_bytes, 0o600)
            changed.append(state_path)
        return ChangeSet(tuple(changed))
    except Exception:
        return _Failure("could not apply the root distribution")


def _read_prior_root_state(state_path: Path) -> tuple[PurePosixPath, ...]:
    if not _lexists(state_path):
        return ()
    _require_regular_file(state_path)
    raw = json.loads(state_path.read_text(encoding="utf-8"))
    if not isinstance(raw, dict) or set(raw) != {"source", "ref", "commit", "version", "distribution_owned"}:
        raise ValueError("invalid root state")
    if not all(isinstance(raw[key], str) and raw[key] and raw[key] == raw[key].strip() for key in ("source", "ref", "commit", "version")):
        raise ValueError("invalid root state")
    if (
        _GITHUB_HTTPS_SOURCE.fullmatch(raw["source"]) is None
        or not _valid_git_ref(raw["ref"])
        or _LOWERCASE_OBJECT_ID.fullmatch(raw["commit"]) is None
        or not isinstance(raw["distribution_owned"], list)
        or any(not isinstance(value, str) for value in raw["distribution_owned"])
    ):
        raise ValueError("invalid root state")
    return _normalize_owned_paths(raw["distribution_owned"], None, require_sources=False)


def _canonical_state(stage: StagedSource, manifest: RootDistributionManifest) -> dict[str, object]:
    return {
        "source": stage.declaration.source,
        "ref": stage.declaration.ref,
        "commit": stage.commit.lower(),
        "version": manifest.version,
        "distribution_owned": [path.as_posix() for path in manifest.distribution_owned],
    }


def _build_sanitized_boundary(stage: StagedSource, scratch_root: Path) -> Path | _Failure:
    sanitized: Path | None = None
    try:
        manifest, owned = _read_profile_manifest(stage)
        _require_private_directory(scratch_root)
        sanitized = Path(tempfile.mkdtemp(prefix="profile-", dir=scratch_root))
        os.chmod(sanitized, 0o700)
        _copy_regular(stage.path / "distribution.yaml", sanitized / "distribution.yaml")
        for owned_path in owned:
            _copy_source_path(stage.path.joinpath(*owned_path.parts), sanitized.joinpath(*owned_path.parts))
        return sanitized
    except Exception:
        if sanitized is not None:
            _safe_remove_tree(sanitized)
        return _Failure("could not sanitize the named profile distribution")


def _read_profile_manifest(stage: StagedSource) -> tuple[Any, tuple[PurePosixPath, ...]]:
    return _read_profile_manifest_at(stage.path, stage.declaration.name, require_sources=True)


def _read_profile_manifest_at(
    root: Path, expected_name: str, *, require_sources: bool
) -> tuple[Any, tuple[PurePosixPath, ...]]:
    manifest_path = root / "distribution.yaml"
    _require_regular_file(manifest_path)
    raw = yaml.load(manifest_path.read_text(encoding="utf-8"), Loader=_UniqueKeyLoader)
    if not isinstance(raw, dict) or any(not isinstance(key, str) for key in raw):
        raise ValueError("profile manifest must be a mapping")
    for key in ("name", "version", "hermes_requires"):
        value = raw.get(key)
        if not isinstance(value, str) or not value or value != value.strip():
            raise ValueError("profile manifest identity invalid")
    if raw["name"] != expected_name:
        raise ValueError("profile manifest identity mismatch")
    raw_owned = raw.get("distribution_owned")
    if not isinstance(raw_owned, list) or not raw_owned or any(not isinstance(item, str) for item in raw_owned):
        raise ValueError("profile manifest owned paths invalid")
    owned = _normalize_owned_paths(raw_owned, root, require_sources=require_sources, profile=True)
    manifest = profile_distribution.read_manifest(root)
    if manifest is None or manifest.name != expected_name:
        raise ValueError("profile manifest identity mismatch")
    if any(
        getattr(manifest, key, None) != raw[key]
        for key in ("name", "version", "hermes_requires")
    ):
        raise ValueError("profile manifest identity mismatch")
    profile_distribution.check_hermes_requires(manifest.hermes_requires, HERMES_VERSION)
    return manifest, owned


def _read_prior_profile_manifest(target: Path, name: str) -> tuple[Any, tuple[PurePosixPath, ...]] | None:
    if not _lexists(target):
        return None
    try:
        return _read_profile_manifest_at(target, name, require_sources=False)
    except Exception:
        return None


def _apply_profile_boundary(stage: StagedSource, data_root: Path, tx: Transaction) -> ChangeSet | _Failure:
    sanitized: Path | None = None
    scratch_root: Path | None = None
    prior_home = os.environ.get("HERMES_HOME")
    home_was_set = "HERMES_HOME" in os.environ
    home_changed = False
    result: ChangeSet | None = None
    primary_failure = False
    cleanup_ok = True
    try:
        _require_data_root(data_root)
        expected_target = data_root / "profiles" / stage.declaration.name
        if stage.declaration.target != expected_target:
            raise ValueError("profile target does not match declaration")
        _require_safe_destination(data_root, expected_target.parent)
        manifest, owned = _read_profile_manifest(stage)
        scratch_root = Path(tempfile.mkdtemp(prefix="hermes-profile-source-"))
        build_result = _build_sanitized_boundary(stage, scratch_root)
        if isinstance(build_result, _Failure):
            raise ValueError("could not build sanitized profile")
        sanitized = build_result
        target = expected_target
        prior = _read_prior_profile_manifest(target, stage.declaration.name)
        if _profile_is_current(target, sanitized, manifest, stage, owned, prior):
            result = ChangeSet(())
        else:
            snapshots = _SnapshotTracker(tx)
            _profile_snapshots(target, owned, manifest, snapshots)
            _remove_stale_profile_paths(target, prior[1] if prior is not None else (), owned, snapshots)
            os.environ["HERMES_HOME"] = str(data_root)
            home_changed = True
            profile_distribution.install_distribution(str(sanitized), name=stage.declaration.name, force=True)
            if target.exists():
                manifest_path = target / "distribution.yaml"
                installed = profile_distribution.read_manifest(target)
                if installed is None:
                    raise ValueError("profile installation did not write a manifest")
                installed.source = stage.declaration.source
                _snapshot(snapshots, manifest_path)
                profile_distribution.write_manifest(target, installed)
            result = ChangeSet(tuple(snapshots.paths))
    except Exception:
        primary_failure = True
    finally:
        if home_changed and home_was_set:
            if prior_home is not None:
                os.environ["HERMES_HOME"] = prior_home
        elif home_changed:
            os.environ.pop("HERMES_HOME", None)
        if sanitized is not None:
            cleanup_ok = _safe_remove_tree(sanitized) and cleanup_ok
        if scratch_root is not None:
            cleanup_ok = _safe_remove_tree(scratch_root) and cleanup_ok
    if primary_failure:
        return _Failure("could not apply the named profile distribution")
    if not cleanup_ok:
        return _Failure("could not clean up the named profile distribution")
    if result is None:
        return _Failure("could not apply the named profile distribution")
    return result


def _profile_snapshots(target: Path, owned: tuple[PurePosixPath, ...], manifest: Any, snapshots: _SnapshotTracker) -> None:
    profiles = target.parent
    if not _lexists(profiles):
        _snapshot(snapshots, profiles)
    target_missing = not _lexists(target)
    if target_missing:
        _snapshot(snapshots, target)
    else:
        _require_regular_directory(target)
    top_levels = {path.parts[0] for path in owned}
    if ".env.template" in top_levels:
        top_levels.remove(".env.template")
        top_levels.add(".env.EXAMPLE")
    top_levels.add("distribution.yaml")
    if getattr(manifest, "env_requires", None):
        top_levels.add(".env.EXAMPLE")
    for directory in _BOOTSTRAP_USER_DIRS:
        if not _lexists(target / directory):
            _snapshot(snapshots, target / directory)
        if directory in {"skills", "skins", "cron"}:
            top_levels.add(directory)
    if target_missing:
        return
    for name in sorted(top_levels):
        destination = target / name
        if name in profile_distribution.USER_OWNED_EXCLUDE:
            continue
        _require_safe_managed_path(target, destination)
        _require_unlinked_managed_regular(destination)
        _snapshot(snapshots, destination)


def _remove_stale_profile_paths(
    target: Path,
    prior_owned: tuple[PurePosixPath, ...],
    next_owned: tuple[PurePosixPath, ...],
    snapshots: _SnapshotTracker,
) -> None:
    stale_owned = tuple(
        owned for owned in prior_owned if not any(owned.is_relative_to(candidate) for candidate in next_owned)
    )
    for owned in sorted(stale_owned, key=lambda path: (len(path.parts), path.as_posix())):
        destination = target.joinpath(*owned.parts)
        _require_safe_managed_path(target, destination)
        if _lexists(destination):
            _snapshot(snapshots, destination)
            _remove_destination(destination)


def _profile_is_current(
    target: Path,
    sanitized: Path,
    manifest: Any,
    stage: StagedSource,
    owned: tuple[PurePosixPath, ...],
    prior: tuple[Any, tuple[PurePosixPath, ...]] | None,
) -> bool:
    if not _lexists(target):
        return False
    _require_regular_directory(target)
    if prior is None:
        return False
    installed, installed_owned = prior
    if _manifest_identity(installed, None, installed_owned) != _manifest_identity(manifest, stage.declaration.source, owned):
        return False
    try:
        payload = tuple(entry for entry in sanitized.iterdir() if entry.name != "distribution.yaml")
        for source in payload:
            destination = target / (".env.EXAMPLE" if source.name == ".env.template" else source.name)
            if not _same_path(source, destination):
                return False
        if getattr(manifest, "env_requires", None) and not _is_regular_file(target / ".env.EXAMPLE"):
            return False
        return all(_is_regular_directory(target / name) for name in _BOOTSTRAP_USER_DIRS)
    except OSError:
        return False


def _manifest_identity(manifest: Any, source: str | None, owned: tuple[PurePosixPath, ...] | None = None) -> str:
    identity = {
        "name": getattr(manifest, "name", ""),
        "version": getattr(manifest, "version", ""),
        "description": getattr(manifest, "description", ""),
        "hermes_requires": getattr(manifest, "hermes_requires", ""),
        "author": getattr(manifest, "author", ""),
        "license": getattr(manifest, "license", ""),
        "env_requires": [requirement.to_dict() for requirement in getattr(manifest, "env_requires", ())],
        "distribution_owned": [path.as_posix() for path in owned]
        if owned is not None
        else sorted(str(path) for path in getattr(manifest, "distribution_owned", ())),
        "source": getattr(manifest, "source", "") if source is None else source,
    }
    return json.dumps(identity, sort_keys=True, separators=(",", ":"))


def _normalize_owned_paths(
    entries: list[str], stage: Path | None, *, require_sources: bool, profile: bool = False
) -> tuple[PurePosixPath, ...]:
    normalized: list[PurePosixPath] = []
    destinations: list[PurePosixPath] = []
    for value in entries:
        if not isinstance(value, str) or not value or value != value.strip() or "\\" in value:
            raise ValueError("invalid distribution owned path")
        candidate = PurePosixPath(value)
        if (
            value.strip() in {".", "/"}
            or candidate.is_absolute()
            or PureWindowsPath(value).is_absolute()
            or not candidate.parts
            or any(part in {"", ".", ".."} for part in candidate.parts)
        ):
            raise ValueError("invalid distribution owned path")
        candidate = PurePosixPath(*candidate.parts)
        _reject_reserved_path(candidate, profile=profile)
        if profile and candidate.parts[0] == ".env.template":
            if candidate != PurePosixPath(".env.template"):
                raise ValueError("invalid distribution owned path")
            if require_sources:
                if stage is None:
                    raise ValueError("missing source stage")
                _require_regular_file(stage / ".env.template")
        destination = (
            PurePosixPath(".env.EXAMPLE")
            if profile and candidate == PurePosixPath(".env.template")
            else candidate
        )
        if candidate in normalized or any(
            candidate.is_relative_to(existing) or existing.is_relative_to(candidate) for existing in normalized
        ):
            raise ValueError("overlapping distribution owned paths")
        if destination in destinations or any(
            destination.is_relative_to(existing) or existing.is_relative_to(destination) for existing in destinations
        ):
            raise ValueError("overlapping distribution owned paths")
        if require_sources:
            if stage is None:
                raise ValueError("missing source stage")
            _validate_source_path(stage.joinpath(*candidate.parts))
        normalized.append(candidate)
        destinations.append(destination)
    return tuple(sorted(normalized, key=lambda path: path.as_posix()))


def _reject_reserved_path(path: PurePosixPath, *, profile: bool = False) -> None:
    lowered = tuple(part.lower() for part in path.parts)
    reserved_top_level = _PROFILE_RESERVED_TOP_LEVEL if profile else _ROOT_RESERVED_TOP_LEVEL
    if lowered[0] in reserved_top_level or any(part in _RESERVED_ANYWHERE for part in lowered):
        raise ValueError("reserved distribution owned path")
    if any(part in _RUNTIME_DATABASES for part in lowered):
        raise ValueError("reserved distribution owned path")


def _valid_git_ref(ref: str) -> bool:
    components = ref.split("/")
    return not (
        ref == "@"
        or ref.startswith(("-", "/"))
        or ref.endswith((".", "/"))
        or ".." in ref
        or "@{" in ref
        or "//" in ref
        or any(component.startswith(".") or component.endswith(".lock") for component in components)
        or any(character in ref for character in " ~^:?*[\\")
        or any(ord(character) < 32 or ord(character) == 127 for character in ref)
    )


def _validate_source_path(path: Path) -> None:
    _require_regular_or_directory(path)
    if path.is_dir():
        with os.scandir(path) as entries:
            for entry in entries:
                _validate_source_path(Path(entry.path))


def _copy_source_path(source: Path, destination: Path) -> None:
    _validate_source_path(source)
    destination.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    if source.is_dir():
        shutil.copytree(source, destination, copy_function=shutil.copy2)
    else:
        _copy_regular(source, destination)


def _same_path(source: Path, destination: Path) -> bool:
    if not _lexists(destination):
        return False
    try:
        source_mode = source.lstat().st_mode
        destination_mode = destination.lstat().st_mode
        if stat.S_ISDIR(source_mode) != stat.S_ISDIR(destination_mode) or stat.S_ISREG(source_mode) != stat.S_ISREG(destination_mode):
            return False
        if stat.S_IMODE(source_mode) != stat.S_IMODE(destination_mode):
            return False
        if stat.S_ISREG(source_mode):
            return source.read_bytes() == destination.read_bytes()
        source_entries = sorted(entry.name for entry in os.scandir(source))
        destination_entries = sorted(entry.name for entry in os.scandir(destination))
        return source_entries == destination_entries and all(
            _same_path(source / name, destination / name) for name in source_entries
        )
    except OSError:
        return False


def _replace_from_source(source: Path, destination: Path, snapshots: _SnapshotTracker) -> None:
    _validate_source_path(source)
    _ensure_destination_parent(destination.parent, snapshots)
    temporary = _temporary_sibling(destination, directory=source.is_dir())
    retired: Path | None = None
    replacement_completed = False
    try:
        if source.is_dir():
            shutil.rmtree(temporary)
            shutil.copytree(source, temporary, copy_function=shutil.copy2)
            _fsync_tree(temporary)
        else:
            _copy_regular(source, temporary)
        try:
            if _lexists(destination):
                retired = _temporary_sibling(destination, directory=False)
                if _lexists(retired):
                    _remove_raw(retired)
                os.replace(destination, retired)
                _fsync_parent(destination.parent)
            os.replace(temporary, destination)
            temporary = None
            _fsync_parent(destination.parent)
            replacement_completed = True
        except Exception:
            if retired is not None and _lexists(retired):
                try:
                    os.replace(retired, destination)
                    retired = None
                    _fsync_parent(destination.parent)
                except Exception:
                    pass
            raise
    finally:
        if temporary is not None and _lexists(temporary):
            _safe_remove_raw(temporary)
        if replacement_completed and retired is not None and _lexists(retired):
            _remove_raw(retired)


def _remove_destination(destination: Path) -> None:
    retired = _temporary_sibling(destination, directory=False)
    if _lexists(retired):
        _remove_raw(retired)
    moved = False
    try:
        os.replace(destination, retired)
        moved = True
        _fsync_parent(destination.parent)
        _remove_raw(retired)
    except Exception:
        if moved and _lexists(retired) and not _lexists(destination):
            try:
                os.replace(retired, destination)
                _fsync_parent(destination.parent)
            except Exception:
                pass
        elif not moved:
            _safe_remove_raw(retired)
        raise


def _temporary_sibling(destination: Path, *, directory: bool) -> Path:
    if directory:
        return Path(tempfile.mkdtemp(prefix=f".{destination.name}.bootstrap-", dir=destination.parent))
    descriptor, name = tempfile.mkstemp(prefix=f".{destination.name}.bootstrap-", dir=destination.parent)
    path = Path(name)
    try:
        os.close(descriptor)
    except Exception:
        _safe_remove_raw(path)
        raise
    return path


def _ensure_destination_parent(parent: Path, snapshots: _SnapshotTracker) -> None:
    missing: list[Path] = []
    current = parent
    while not _lexists(current):
        missing.append(current)
        current = current.parent
    _require_regular_directory(current)
    for directory in reversed(missing):
        _snapshot(snapshots, directory)
        directory.mkdir(mode=0o700)
        _fsync_parent(directory.parent)
    _require_regular_directory(parent)


def _ensure_state_parent(data_root: Path, parent: Path, snapshots: _SnapshotTracker) -> None:
    if _lexists(parent):
        _require_regular_directory(parent)
        return
    _snapshot(snapshots, parent)
    parent.mkdir(mode=0o700, parents=False, exist_ok=False)
    _fsync_parent(parent.parent)


def _atomic_write(destination: Path, content: bytes, mode: int) -> None:
    if not _lexists(destination.parent):
        raise ValueError("state parent is unavailable")
    temporary = _temporary_sibling(destination, directory=False)
    try:
        with temporary.open("wb") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, mode)
        os.replace(temporary, destination)
        _fsync_parent(destination.parent)
        temporary = None
    finally:
        if temporary is not None and _lexists(temporary):
            _remove_raw(temporary)


def _same_regular_bytes(path: Path, expected: bytes) -> bool:
    try:
        return _lexists(path) and stat.S_ISREG(path.lstat().st_mode) and path.read_bytes() == expected and stat.S_IMODE(path.stat().st_mode) == 0o600
    except OSError:
        return False


def _require_data_root(data_root: Path) -> None:
    _require_regular_directory(data_root)


def _require_safe_destination(data_root: Path, destination_parent: Path) -> None:
    try:
        relative = destination_parent.relative_to(data_root)
    except ValueError as error:
        raise ValueError("managed destination escapes data root") from error
    current = data_root
    _require_regular_directory(current)
    for part in relative.parts:
        current = current / part
        if not _lexists(current):
            break
        _require_regular_directory(current)


def _require_safe_managed_path(data_root: Path, destination: Path) -> None:
    _require_safe_destination(data_root, destination.parent)
    if not _lexists(destination):
        return
    try:
        mode = destination.lstat().st_mode
        if stat.S_ISLNK(mode) or not (stat.S_ISREG(mode) or stat.S_ISDIR(mode)):
            raise ValueError("managed destination is unsafe")
    except OSError as error:
        raise ValueError("managed destination is unsafe") from error


def _require_unlinked_managed_regular(destination: Path) -> None:
    if not _lexists(destination):
        return
    try:
        status = destination.lstat()
    except OSError as error:
        raise ValueError("managed destination is unsafe") from error
    if stat.S_ISREG(status.st_mode) and status.st_nlink != 1:
        raise ValueError("managed regular file has multiple links")


def _require_regular_directory(path: Path) -> None:
    try:
        mode = path.lstat().st_mode
    except OSError as error:
        raise ValueError("required directory is unavailable") from error
    if stat.S_ISLNK(mode) or not stat.S_ISDIR(mode):
        raise ValueError("unsafe directory")


def _require_private_directory(path: Path) -> None:
    if _lexists(path):
        _require_regular_directory(path)
    else:
        path.mkdir(mode=0o700, parents=True, exist_ok=False)
    os.chmod(path, 0o700)


def _require_regular_or_directory(path: Path) -> None:
    try:
        mode = path.lstat().st_mode
    except OSError as error:
        raise ValueError("unsafe distribution source") from error
    if stat.S_ISLNK(mode) or not (stat.S_ISREG(mode) or stat.S_ISDIR(mode)):
        raise ValueError("unsafe distribution source")


def _require_regular_file(path: Path) -> None:
    _require_regular_or_directory(path)
    if not path.is_file():
        raise ValueError("expected regular file")


def _copy_regular(source: Path, destination: Path) -> None:
    _require_regular_or_directory(source)
    if not source.is_file():
        raise ValueError("expected regular file")
    shutil.copy2(source, destination)
    _fsync_file(destination)


def _snapshot(snapshots: _SnapshotTracker, path: Path) -> bool:
    return snapshots.snapshot(path)


def _lexists(path: Path) -> bool:
    return os.path.lexists(path)


def _remove_raw(path: Path) -> None:
    mode = path.lstat().st_mode
    if stat.S_ISDIR(mode) and not stat.S_ISLNK(mode):
        shutil.rmtree(path)
    else:
        path.unlink()
    _fsync_parent(path.parent)


def _safe_remove_raw(path: Path) -> None:
    try:
        _remove_raw(path)
    except Exception:
        pass


def _fsync_file(path: Path) -> None:
    descriptor: int | None = None
    failure = False
    try:
        descriptor = os.open(path, os.O_RDONLY)
        os.fsync(descriptor)
    except OSError:
        failure = True
    finally:
        if descriptor is not None:
            try:
                os.close(descriptor)
            except OSError:
                failure = True
    if failure:
        raise ValueError("could not synchronize distribution file")


def _fsync_tree(path: Path) -> None:
    if path.is_file():
        _fsync_file(path)
        return
    for current, directories, files in os.walk(path, topdown=False):
        current_path = Path(current)
        for name in files:
            _fsync_file(current_path / name)
        if directories or files:
            _fsync_parent(current_path)


def _fsync_parent(parent: Path) -> None:
    descriptor: int | None = None
    failure = False
    try:
        descriptor = os.open(parent, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
        os.fsync(descriptor)
    except OSError:
        failure = True
    finally:
        if descriptor is not None:
            try:
                os.close(descriptor)
            except OSError:
                failure = True
    if failure:
        raise ValueError("could not synchronize distribution directory")


def _safe_remove_tree(path: Path) -> bool:
    try:
        shutil.rmtree(path)
    except Exception:
        return False
    return True


def _is_regular_file(path: Path) -> bool:
    try:
        return stat.S_ISREG(path.lstat().st_mode)
    except OSError:
        return False


def _is_regular_directory(path: Path) -> bool:
    try:
        return stat.S_ISDIR(path.lstat().st_mode)
    except OSError:
        return False
