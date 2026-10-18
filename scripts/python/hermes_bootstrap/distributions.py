"""Apply Hermes root and named-profile distributions within owned paths."""

from __future__ import annotations

import json
import os
import shutil
import stat
import tempfile
from dataclasses import dataclass
from pathlib import Path, PurePosixPath, PureWindowsPath

import yaml
from hermes_cli import __version__ as HERMES_VERSION
from hermes_cli import profile_distribution

from .errors import ApplyError
from .git import StagedSource
from .google_gmail import is_google_gmail_configuration

_ROOT_MANIFEST = "root-distribution.yaml"
_ROOT_STATE = PurePosixPath(".bootstrap/root-distribution-state.json")
_ROOT_KEYS = frozenset({"schema_version", "name", "version", "description", "hermes_requires", "distribution_owned"})
_ROOT_REQUIRED_KEYS = frozenset({"schema_version", "name", "version", "hermes_requires", "distribution_owned"})
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
_PM_RUNTIME_ROOT_DIRS = frozenset({"tools", "installs", "cache"})
_ROOT_RESERVED_TOP_LEVEL = _RESERVED_TOP_LEVEL | _PM_RUNTIME_ROOT_DIRS | frozenset(
    name.lower() for name in profile_distribution.USER_OWNED_EXCLUDE
)
_PROFILE_RESERVED_TOP_LEVEL = frozenset(
    name.lower() for name in profile_distribution.USER_OWNED_EXCLUDE
) | _PM_RUNTIME_ROOT_DIRS


@dataclass(frozen=True)
class RootDistributionManifest:
    version: str
    distribution_owned: tuple[PurePosixPath, ...]


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
    return RootDistributionManifest(version, normalized)


def apply_root_distribution(stage: StagedSource, data_root: Path) -> None:
    """Replace only root-owned paths and persist canonical ownership state."""

    try:
        _require_data_root(data_root)
        if stage.declaration.name != "default" or stage.declaration.target != data_root:
            raise ValueError("invalid root declaration")
        manifest = _read_root_manifest(stage.path)
        state_path = data_root.joinpath(*_ROOT_STATE.parts)
        prior_owned = _read_prior_root_state(state_path)
        next_owned = manifest.distribution_owned
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
                _remove_raw(destination)
        next_set = set(next_owned)
        for owned in sorted((*next_owned, *deferred_stale), key=lambda path: path.as_posix()):
            destination = data_root.joinpath(*owned.parts)
            _require_safe_managed_path(data_root, destination)
            if owned in next_set:
                source = stage.path.joinpath(*owned.parts)
                if _same_distribution_path(source, destination):
                    continue
                _ensure_destination_parent(destination.parent)
                _replace_from_source(source, destination)
            elif _lexists(destination):
                _remove_raw(destination)
        state = _canonical_state(stage, manifest)
        state_bytes = (json.dumps(state, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")
        _require_safe_managed_path(data_root, state_path)
        if not _same_regular_bytes(state_path, state_bytes):
            _ensure_destination_parent(state_path.parent)
            _atomic_write(state_path, state_bytes, 0o600)
    except Exception:
        raise ApplyError("could not apply the root distribution") from None


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
        not isinstance(raw["distribution_owned"], list)
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


def _read_profile_manifest(
    stage: StagedSource,
) -> tuple[profile_distribution.DistributionManifest, tuple[PurePosixPath, ...]]:
    return _read_profile_manifest_at(stage.path, stage.declaration.name, require_sources=True)


def _read_profile_manifest_at(
    root: Path, expected_name: str, *, require_sources: bool
) -> tuple[profile_distribution.DistributionManifest, tuple[PurePosixPath, ...]]:
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
    manifest = profile_distribution.DistributionManifest.from_dict(raw)
    profile_distribution.check_hermes_requires(manifest.hermes_requires, HERMES_VERSION)
    return manifest, owned


def apply_profile_distribution(
    stage: StagedSource,
    data_root: Path,
) -> None:
    """Install one absent named profile privately, then publish it intact."""

    private_home: Path | None = None
    prior_home = os.environ.get("HERMES_HOME")
    home_was_set = "HERMES_HOME" in os.environ
    home_changed = False
    cleanup_ok = True
    try:
        _require_data_root(data_root)
        expected_target = data_root / "profiles" / stage.declaration.name
        if stage.declaration.target != expected_target:
            raise ValueError("profile target does not match declaration")
        _require_safe_destination(data_root, expected_target.parent)
        if _lexists(expected_target):
            raise ValueError("named profile already exists")
        _read_profile_manifest(stage)
        private_home = Path(tempfile.mkdtemp(prefix=".hermes-profile-home-", dir=data_root.parent))
        install_target = private_home / "profiles" / stage.declaration.name
        os.environ["HERMES_HOME"] = str(private_home)
        home_changed = True
        installed = profile_distribution.install_distribution(
            str(stage.path),
            name=stage.declaration.name,
            force=False,
        ).manifest
        _require_regular_directory(install_target)
        installed.source = stage.declaration.source
        profile_distribution.write_manifest(install_target, installed)
        profiles = expected_target.parent
        if not _lexists(profiles):
            profiles.mkdir(mode=0o700)
        else:
            _require_regular_directory(profiles)
        if _lexists(expected_target):
            raise ValueError("named profile already exists")
        install_target.rename(expected_target)
    except Exception:
        raise ApplyError("could not apply the named profile distribution") from None
    finally:
        if home_changed and home_was_set:
            if prior_home is not None:
                os.environ["HERMES_HOME"] = prior_home
        elif home_changed:
            os.environ.pop("HERMES_HOME", None)
        if private_home is not None:
            cleanup_ok = _safe_remove_tree(private_home) and cleanup_ok
    if not cleanup_ok:
        raise ApplyError("could not clean up the named profile distribution")


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
            _validate_source_path(stage.joinpath(*candidate.parts), owned_path=candidate)
        normalized.append(candidate)
        destinations.append(destination)
    return tuple(sorted(normalized, key=lambda path: path.as_posix()))


def _reject_reserved_path(path: PurePosixPath, *, profile: bool = False) -> None:
    _reject_unsupported_cron_path(path)
    lowered = tuple(part.lower() for part in path.parts)
    reserved_top_level = _PROFILE_RESERVED_TOP_LEVEL if profile else _ROOT_RESERVED_TOP_LEVEL
    if lowered[0] in reserved_top_level or any(part in _RESERVED_ANYWHERE for part in lowered):
        raise ValueError("reserved distribution owned path")
    if any(part in _RUNTIME_DATABASES for part in lowered):
        raise ValueError("reserved distribution owned path")


def _reject_unsupported_cron_path(path: PurePosixPath) -> None:
    # Current Hermes imports only the job store, never arbitrary cron siblings.
    if path.parts[0].lower() == "cron" and path not in {
        PurePosixPath("cron"), PurePosixPath("cron/jobs.json")
    }:
        raise ValueError("unsupported cron distribution path")


def _validate_source_path(path: Path, *, owned_path: PurePosixPath | None = None) -> None:
    if owned_path is not None:
        _reject_unsupported_cron_path(owned_path)
    _require_regular_or_directory(path)
    if path.is_dir():
        with os.scandir(path) as entries:
            for entry in entries:
                _validate_source_path(
                    Path(entry.path),
                    owned_path=owned_path / entry.name if owned_path is not None else None,
                )


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


def _same_profile_payload_path(source: Path, destination: Path) -> bool:
    if _same_path(source, destination):
        return True
    if source.name != "config.yaml" or not _lexists(destination):
        return False
    try:
        source_mode = source.lstat().st_mode
        destination_mode = destination.lstat().st_mode
        return (
            stat.S_ISREG(source_mode)
            and stat.S_ISREG(destination_mode)
            and stat.S_IMODE(source_mode) == 0o644
            and stat.S_IMODE(destination_mode) == 0o600
            and source.read_bytes() == destination.read_bytes()
        )
    except OSError:
        return False

def _same_distribution_path(source: Path, destination: Path) -> bool:
    """Compare distribution files while ignoring managed config sections."""

    if _same_profile_payload_path(source, destination):
        return True
    if source.name != "config.yaml" or destination.name != "config.yaml":
        return False
    try:
        source_config = yaml.safe_load(source.read_text(encoding="utf-8"))
        destination_config = yaml.safe_load(destination.read_text(encoding="utf-8"))
        if not isinstance(source_config, dict) or not isinstance(destination_config, dict):
            return False
        return without_bootstrap_managed_config(
            source_config
        ) == without_bootstrap_managed_config(destination_config)
    except (OSError, UnicodeError, TypeError, ValueError, yaml.YAMLError):
        return False


def _without_bootstrap_onepassword(config: dict[object, object]) -> dict[object, object]:
    result = dict(config)
    secrets = result.get("secrets")
    if not isinstance(secrets, dict):
        return result
    remaining_secrets = dict(secrets)
    remaining_secrets.pop("onepassword", None)
    if remaining_secrets:
        result["secrets"] = remaining_secrets
    else:
        result.pop("secrets", None)
    return result


def without_bootstrap_managed_config(
    config: dict[object, object],
) -> dict[object, object]:
    """Compare distribution content without bootstrap-owned config additions."""

    result = _without_bootstrap_onepassword(config)
    context = result.get("context")
    if isinstance(context, dict):
        retained_context = dict(context)
        retained_context.pop("engine", None)
        if retained_context:
            result["context"] = retained_context
        else:
            result.pop("context", None)

    plugins = result.get("plugins")
    if isinstance(plugins, dict):
        retained_plugins = dict(plugins)
        for key in ("enabled", "disabled"):
            values = retained_plugins.get(key)
            if not isinstance(values, list):
                continue
            retained_values = [item for item in values if item != "hermes-lcm"]
            if retained_values:
                retained_plugins[key] = retained_values
            else:
                retained_plugins.pop(key, None)
        if retained_plugins:
            result["plugins"] = retained_plugins
        else:
            result.pop("plugins", None)

    platforms = result.get("platforms")
    if isinstance(platforms, dict):
        discord = platforms.get("discord")
        if isinstance(discord, dict):
            retained_discord = dict(discord)
            retained_discord.pop("allow_bots", None)
            extra = discord.get("extra")
            if isinstance(extra, dict):
                retained_extra = dict(extra)
                retained_extra.pop("allow_bots", None)
                if retained_extra:
                    retained_discord["extra"] = retained_extra
                else:
                    retained_discord.pop("extra", None)
            retained_platforms = dict(platforms)
            if retained_discord:
                retained_platforms["discord"] = retained_discord
            else:
                retained_platforms.pop("discord", None)
            if retained_platforms:
                result["platforms"] = retained_platforms
            else:
                result.pop("platforms", None)

    mcp_servers = result.get("mcp_servers")
    if isinstance(mcp_servers, dict):
        gmail = mcp_servers.get("gmail")
        if is_google_gmail_configuration(gmail):
            retained_servers = dict(mcp_servers)
            retained_servers.pop("gmail")
            if retained_servers:
                result["mcp_servers"] = retained_servers
            else:
                result.pop("mcp_servers", None)

    return result


def _replace_from_source(source: Path, destination: Path) -> None:
    source_is_directory = source.is_dir()
    temporary = _temporary_sibling(destination, directory=source_is_directory)
    try:
        if source_is_directory:
            shutil.copytree(source, temporary, copy_function=shutil.copy2, dirs_exist_ok=True)
        else:
            _copy_regular(source, temporary)
        if _lexists(destination) and (source_is_directory or destination.is_dir()):
            _remove_raw(destination)
        os.replace(temporary, destination)
        temporary = None
    finally:
        if temporary is not None and _lexists(temporary):
            _safe_remove_raw(temporary)


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


def _ensure_destination_parent(parent: Path) -> None:
    missing: list[Path] = []
    current = parent
    while not _lexists(current):
        missing.append(current)
        current = current.parent
    _require_regular_directory(current)
    for directory in reversed(missing):
        directory.mkdir(mode=0o700)
    _require_regular_directory(parent)


def _atomic_write(destination: Path, content: bytes, mode: int) -> None:
    if not _lexists(destination.parent):
        raise ValueError("state parent is unavailable")
    temporary = _temporary_sibling(destination, directory=False)
    try:
        with temporary.open("wb") as handle:
            handle.write(content)
        os.chmod(temporary, mode)
        os.replace(temporary, destination)
        temporary = None
    finally:
        if temporary is not None and _lexists(temporary):
            _remove_raw(temporary)


def _same_regular_bytes(path: Path, expected: bytes) -> bool:
    try:
        metadata = path.lstat()
        return stat.S_ISREG(metadata.st_mode) and stat.S_IMODE(metadata.st_mode) == 0o600 and path.read_bytes() == expected
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


def _lexists(path: Path) -> bool:
    return os.path.lexists(path)


def _remove_raw(path: Path) -> None:
    mode = path.lstat().st_mode
    if stat.S_ISDIR(mode) and not stat.S_ISLNK(mode):
        shutil.rmtree(path)
    else:
        path.unlink()


def _safe_remove_raw(path: Path) -> None:
    try:
        _remove_raw(path)
    except Exception:
        pass


def _safe_remove_tree(path: Path) -> bool:
    try:
        shutil.rmtree(path)
    except Exception:
        return False
    return True
