"""Apply Hermes root and named-profile distribution snapshots safely."""

from __future__ import annotations

import json
import os
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
_RESERVED_TOP_LEVEL = frozenset(
    {
        ".bootstrap",
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


class Transaction(Protocol):
    def snapshot(self, path: Path) -> None: ...


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
        or not isinstance(hermes_requires, str)
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
        state_path = data_root.joinpath(*_ROOT_STATE.parts)
        prior_owned = _read_prior_root_state(state_path)
        next_owned = manifest.distribution_owned
        next_set = set(next_owned)
        changed: list[Path] = []
        for owned in sorted(set(prior_owned) | next_set, key=lambda path: path.as_posix()):
            destination = data_root.joinpath(*owned.parts)
            _require_safe_managed_path(data_root, destination)
            if owned in next_set:
                source = stage.path.joinpath(*owned.parts)
                if _same_path(source, destination):
                    continue
                _ensure_destination_parent(destination.parent, tx)
                _snapshot(tx, destination)
                _replace_from_source(source, destination, tx)
                changed.append(destination)
            elif _lexists(destination):
                _snapshot(tx, destination)
                _remove_destination(destination)
                changed.append(destination)
        state = _canonical_state(stage, manifest)
        state_bytes = (json.dumps(state, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")
        _require_safe_managed_path(data_root, state_path)
        if not _same_regular_bytes(state_path, state_bytes):
            _ensure_state_parent(data_root, state_path.parent, tx)
            _require_safe_destination(data_root, state_path.parent)
            _snapshot(tx, state_path)
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
    if (
        not all(isinstance(raw[key], str) and raw[key] for key in ("source", "ref", "commit", "version"))
        or not isinstance(raw["distribution_owned"], list)
        or any(not isinstance(value, str) for value in raw["distribution_owned"])
    ):
        raise ValueError("invalid root state")
    commit = raw["commit"]
    if len(commit) not in (40, 64) or any(character not in "0123456789abcdef" for character in commit.lower()):
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
    manifest_path = stage.path / "distribution.yaml"
    _require_regular_file(manifest_path)
    raw = yaml.load(manifest_path.read_text(encoding="utf-8"), Loader=_UniqueKeyLoader)
    if not isinstance(raw, dict) or any(not isinstance(key, str) for key in raw):
        raise ValueError("profile manifest must be a mapping")
    raw_owned = raw.get("distribution_owned", [])
    if not isinstance(raw_owned, list) or any(not isinstance(item, str) for item in raw_owned):
        raise ValueError("profile manifest owned paths invalid")
    owned = _normalize_owned_paths(raw_owned, stage.path, require_sources=True)
    manifest = profile_distribution.read_manifest(stage.path)
    if manifest is None or manifest.name != stage.declaration.name:
        raise ValueError("profile manifest identity mismatch")
    profile_distribution.check_hermes_requires(manifest.hermes_requires, HERMES_VERSION)
    return manifest, owned


def _apply_profile_boundary(stage: StagedSource, data_root: Path, tx: Transaction) -> ChangeSet | _Failure:
    sanitized: Path | None = None
    scratch_root: Path | None = None
    prior_home: str | None = None
    home_was_set = False
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
        snapshots = _profile_snapshots(target, owned, manifest, tx)
        prior_home = os.environ.get("HERMES_HOME")
        home_was_set = "HERMES_HOME" in os.environ
        os.environ["HERMES_HOME"] = str(data_root)
        profile_distribution.install_distribution(str(sanitized), name=stage.declaration.name, force=True)
        if target.exists():
            manifest_path = target / "distribution.yaml"
            installed = profile_distribution.read_manifest(target)
            if installed is None:
                raise ValueError("profile installation did not write a manifest")
            installed.source = stage.declaration.source
            if target not in snapshots and manifest_path not in snapshots:
                _snapshot(tx, manifest_path)
                snapshots.append(manifest_path)
            profile_distribution.write_manifest(target, installed)
        result = ChangeSet(tuple(snapshots))
    except Exception:
        primary_failure = True
    finally:
        if home_was_set:
            if prior_home is not None:
                os.environ["HERMES_HOME"] = prior_home
        else:
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


def _profile_snapshots(target: Path, owned: tuple[PurePosixPath, ...], manifest: Any, tx: Transaction) -> list[Path]:
    if not _lexists(target):
        _snapshot(tx, target)
        return [target]
    _require_regular_directory(target)
    snapshots: list[Path] = []
    top_levels = {path.parts[0] for path in owned}
    if ".env.template" in top_levels:
        top_levels.remove(".env.template")
        top_levels.add(".env.EXAMPLE")
    top_levels.add("distribution.yaml")
    if getattr(manifest, "env_requires", None):
        top_levels.add(".env.EXAMPLE")
    for directory in ("skills", "skins", "cron"):
        if not _lexists(target / directory):
            top_levels.add(directory)
    for name in sorted(top_levels):
        if name in profile_distribution.USER_OWNED_EXCLUDE:
            continue
        destination = target / name
        _require_safe_managed_path(target, destination)
        _snapshot(tx, destination)
        snapshots.append(destination)
    return snapshots


def _normalize_owned_paths(
    entries: list[str], stage: Path | None, *, require_sources: bool
) -> tuple[PurePosixPath, ...]:
    normalized: list[PurePosixPath] = []
    for value in entries:
        if not isinstance(value, str) or not value or not value.strip() or "\\" in value:
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
        _reject_reserved_path(candidate)
        if candidate in normalized or any(
            candidate.is_relative_to(existing) or existing.is_relative_to(candidate) for existing in normalized
        ):
            raise ValueError("overlapping distribution owned paths")
        if require_sources:
            if stage is None:
                raise ValueError("missing source stage")
            _validate_source_path(stage.joinpath(*candidate.parts))
        normalized.append(candidate)
    return tuple(sorted(normalized, key=lambda path: path.as_posix()))


def _reject_reserved_path(path: PurePosixPath) -> None:
    lowered = tuple(part.lower() for part in path.parts)
    if lowered[0] in _RESERVED_TOP_LEVEL or any(part in _RESERVED_ANYWHERE for part in lowered):
        raise ValueError("reserved distribution owned path")
    if any(part in _RUNTIME_DATABASES for part in lowered):
        raise ValueError("reserved distribution owned path")


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


def _replace_from_source(source: Path, destination: Path, tx: Transaction) -> None:
    _validate_source_path(source)
    _ensure_destination_parent(destination.parent, tx)
    temporary = _temporary_sibling(destination, directory=source.is_dir())
    retired: Path | None = None
    try:
        if source.is_dir():
            shutil.rmtree(temporary)
            shutil.copytree(source, temporary, copy_function=shutil.copy2)
        else:
            _copy_regular(source, temporary)
        if _lexists(destination):
            retired = _temporary_sibling(destination, directory=False)
            if _lexists(retired):
                _remove_raw(retired)
            os.replace(destination, retired)
        os.replace(temporary, destination)
        temporary = None
    finally:
        if temporary is not None and _lexists(temporary):
            _remove_raw(temporary)
        if retired is not None and _lexists(retired):
            _remove_raw(retired)


def _remove_destination(destination: Path) -> None:
    retired = _temporary_sibling(destination, directory=False)
    if _lexists(retired):
        _remove_raw(retired)
    try:
        os.replace(destination, retired)
    finally:
        if _lexists(retired):
            _remove_raw(retired)


def _temporary_sibling(destination: Path, *, directory: bool) -> Path:
    if directory:
        return Path(tempfile.mkdtemp(prefix=f".{destination.name}.bootstrap-", dir=destination.parent))
    descriptor, name = tempfile.mkstemp(prefix=f".{destination.name}.bootstrap-", dir=destination.parent)
    os.close(descriptor)
    return Path(name)


def _ensure_destination_parent(parent: Path, tx: Transaction) -> None:
    missing: list[Path] = []
    current = parent
    while not _lexists(current):
        missing.append(current)
        current = current.parent
    _require_regular_directory(current)
    for directory in reversed(missing):
        _snapshot(tx, directory)
        directory.mkdir(mode=0o700)
    _require_regular_directory(parent)


def _ensure_state_parent(data_root: Path, parent: Path, tx: Transaction) -> None:
    if _lexists(parent):
        _require_regular_directory(parent)
        return
    _snapshot(tx, parent)
    parent.mkdir(mode=0o700, parents=False, exist_ok=False)


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


def _snapshot(tx: Transaction, path: Path) -> None:
    tx.snapshot(path)


def _lexists(path: Path) -> bool:
    return os.path.lexists(path)


def _remove_raw(path: Path) -> None:
    mode = path.lstat().st_mode
    if stat.S_ISDIR(mode) and not stat.S_ISLNK(mode):
        shutil.rmtree(path)
    else:
        path.unlink()


def _safe_remove_tree(path: Path) -> bool:
    try:
        shutil.rmtree(path)
    except Exception:
        return False
    return True
