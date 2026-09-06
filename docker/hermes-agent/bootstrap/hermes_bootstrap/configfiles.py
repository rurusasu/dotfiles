"""Transactional reconciliation of managed Hermes configuration sections."""

from __future__ import annotations

import os
import json
import stat
from collections.abc import Sequence
from pathlib import Path

import yaml

from .distributions import _atomic_write
from .envfiles import LEGACY_SLACK_KEYS
from .errors import ApplyError
from .models import BootstrapManifest
from .onepassword import build_onepassword_config, managed_environment_bindings
from .transaction import Transaction


_XAPI_MCP = {
    "url": "http://xapi-mcp:8080/mcp",
    "connect_timeout": 300,
}
_MANAGED_ENVIRONMENT_STATE = Path(".bootstrap/onepassword-managed-environment-state.json")
_LEGACY_MANAGED_ENVIRONMENT_NAMES = frozenset(
    {
        "HERMES_DASHBOARD_BASIC_AUTH_USERNAME",
        "GITHUB_PERSONAL_ACCESS_TOKEN",
        "GH_TOKEN",
        "GITHUB_TOKEN",
        "DISCORD_BOT_TOKEN",
        "DISCORD_ALLOWED_USERS",
        "DISCORD_ALLOW_BOTS",
        "XAI_API_KEY",
    }
)


def reconcile_xapi_configurations(
    targets: Sequence[Path],
    transaction: Transaction,
) -> None:
    """Install the canonical internal X API MCP in every runtime profile."""

    try:
        for target in targets:
            path = target / "config.yaml"
            metadata = path.lstat()
            if (
                stat.S_ISLNK(metadata.st_mode)
                or not stat.S_ISREG(metadata.st_mode)
                or metadata.st_nlink != 1
            ):
                raise ApplyError("invalid Hermes X API configuration file")
            config = yaml.safe_load(path.read_text(encoding="utf-8"))
            if not isinstance(config, dict):
                raise ApplyError("invalid Hermes X API configuration")
            mcp_servers = config.get("mcp_servers")
            if mcp_servers is None:
                mcp_servers = {}
            if not isinstance(mcp_servers, dict):
                raise ApplyError("invalid Hermes X API configuration")
            if mcp_servers.get("xapi") == _XAPI_MCP:
                continue

            candidate = dict(config)
            candidate_servers = dict(mcp_servers)
            candidate_servers["xapi"] = dict(_XAPI_MCP)
            candidate["mcp_servers"] = candidate_servers
            content = yaml.safe_dump(candidate, sort_keys=False).encode("utf-8")
            transaction.snapshot(path)
            _atomic_write(path, content, stat.S_IMODE(metadata.st_mode))
    except ApplyError:
        raise
    except (OSError, TypeError, UnicodeError, ValueError, yaml.YAMLError):
        raise ApplyError("could not reconcile Hermes X API configuration") from None


def validate_xapi_configurations(targets: Sequence[Path]) -> None:
    """Require the canonical internal X API MCP in every runtime profile."""

    try:
        for target in targets:
            path = target / "config.yaml"
            metadata = path.lstat()
            if (
                stat.S_ISLNK(metadata.st_mode)
                or not stat.S_ISREG(metadata.st_mode)
                or metadata.st_nlink != 1
            ):
                raise ApplyError("installed Hermes X API configuration is invalid")
            config = yaml.safe_load(path.read_text(encoding="utf-8"))
            if not isinstance(config, dict):
                raise ApplyError("installed Hermes X API configuration is invalid")
            mcp_servers = config.get("mcp_servers")
            if not isinstance(mcp_servers, dict) or mcp_servers.get("xapi") != _XAPI_MCP:
                raise ApplyError("installed Hermes X API configuration is invalid")
    except ApplyError:
        raise
    except (OSError, TypeError, UnicodeError, ValueError, yaml.YAMLError):
        raise ApplyError("installed Hermes X API configuration is invalid") from None


def reconcile_onepassword_cli_permissions(
    data_root: Path,
    transaction: Transaction,
) -> None:
    """Keep the persisted 1Password CLI state private without following links."""

    path = data_root / ".config" / "op"
    try:
        metadata = path.lstat()
    except FileNotFoundError:
        return
    except OSError:
        raise ApplyError("could not secure 1Password CLI configuration") from None
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
        raise ApplyError("invalid 1Password CLI configuration directory")
    if stat.S_IMODE(metadata.st_mode) == 0o700:
        return

    descriptor: int | None = None
    try:
        transaction.snapshot(path)
        descriptor = os.open(
            path,
            os.O_RDONLY | os.O_CLOEXEC | os.O_DIRECTORY | os.O_NOFOLLOW,
        )
        opened = os.fstat(descriptor)
        current = path.lstat()
        if (
            not stat.S_ISDIR(opened.st_mode)
            or stat.S_ISLNK(current.st_mode)
            or (opened.st_dev, opened.st_ino) != (current.st_dev, current.st_ino)
        ):
            raise OSError
        os.fchmod(descriptor, 0o700)
        secured = os.fstat(descriptor)
        current = path.lstat()
        if (
            stat.S_IMODE(secured.st_mode) != 0o700
            or stat.S_ISLNK(current.st_mode)
            or (secured.st_dev, secured.st_ino) != (current.st_dev, current.st_ino)
        ):
            raise OSError
    except ApplyError:
        raise
    except (OSError, ValueError):
        raise ApplyError("could not secure 1Password CLI configuration") from None
    finally:
        if descriptor is not None:
            os.close(descriptor)


def reconcile_onepassword_configurations(
    manifest: BootstrapManifest,
    targets: Sequence[tuple[str, Path]],
    transaction: Transaction,
) -> None:
    """Merge managed onepassword settings into each Hermes config atomically."""

    if not manifest.onepassword_items:
        return

    data_root = targets[0][1] if targets else None
    try:
        if data_root is None:
            raise ApplyError("managed Hermes configuration targets are empty")
        previous_managed_names = _read_managed_environment_state(data_root)
        current_managed_names = {
            environment_name
            for profile, _target in targets
            for environment_name, _item, _field in managed_environment_bindings(
                manifest, profile
            )
        }
        managed_names = (
            previous_managed_names
            | _LEGACY_MANAGED_ENVIRONMENT_NAMES
            | current_managed_names
        )
        for profile, target in targets:
            path = target / "config.yaml"
            try:
                metadata = path.lstat()
            except OSError:
                raise ApplyError("managed Hermes configuration is unavailable") from None
            if (
                stat.S_ISLNK(metadata.st_mode)
                or not stat.S_ISREG(metadata.st_mode)
                or metadata.st_nlink != 1
            ):
                raise ApplyError("managed Hermes configuration is unsafe")
            try:
                original_content = path.read_text(encoding="utf-8")
            except (OSError, UnicodeError):
                raise ApplyError("managed Hermes configuration is unreadable") from None
            try:
                config = yaml.safe_load(original_content)
            except (OSError, UnicodeError, yaml.YAMLError):
                raise ApplyError("managed Hermes configuration is invalid") from None
            if not isinstance(config, dict):
                raise ApplyError("managed Hermes configuration is invalid")

            secrets = config.get("secrets")
            if secrets is None:
                secrets = {}
            if not isinstance(secrets, dict):
                raise ApplyError("managed Hermes secrets configuration is invalid")
            onepassword = secrets.get("onepassword")
            if onepassword is None:
                onepassword = {}
            if not isinstance(onepassword, dict):
                raise ApplyError("managed Hermes 1Password configuration is invalid")
            existing_env = onepassword.get("env")
            if existing_env is None:
                existing_env = {}
            if not isinstance(existing_env, dict):
                raise ApplyError("managed Hermes 1Password environment is invalid")
            retained_env = {
                key: value
                for key, value in existing_env.items()
                if key not in LEGACY_SLACK_KEYS and key not in managed_names
            }

            managed = build_onepassword_config(manifest, profile)
            managed_config = dict(managed)
            managed_config["env"] = {}
            if "secrets" not in config:
                content = (
                    original_content.rstrip("\n")
                    + "\n"
                    + yaml.safe_dump(
                        {"secrets": {"onepassword": managed_config}},
                        sort_keys=False,
                    )
                ).encode("utf-8")
                if path.read_bytes() == content:
                    continue
                transaction.snapshot(path)
                _atomic_write(path, content, stat.S_IMODE(metadata.st_mode))
                continue
            if onepassword == managed_config and not existing_env:
                continue
            merged_onepassword = dict(onepassword)
            merged_onepassword.update(managed_config)
            merged_onepassword["env"] = {
                **retained_env,
            }
            merged_secrets = dict(secrets)
            merged_secrets["onepassword"] = merged_onepassword
            candidate = dict(config)
            candidate["secrets"] = merged_secrets
            content = yaml.safe_dump(candidate, sort_keys=False).encode("utf-8")
            if path.read_bytes() == content:
                continue
            transaction.snapshot(path)
            _atomic_write(path, content, stat.S_IMODE(metadata.st_mode))
        state_path = data_root / _MANAGED_ENVIRONMENT_STATE
        state_content = (
            json.dumps(
                {
                    "schema_version": 1,
                    "environment_names": sorted(current_managed_names),
                },
                separators=(",", ":"),
            )
            + "\n"
        ).encode("utf-8")
        if not state_path.exists() or state_path.read_bytes() != state_content:
            transaction.snapshot(state_path)
            state_path.parent.mkdir(mode=0o700, exist_ok=True)
            _atomic_write(state_path, state_content, 0o600)
    except (OSError, TypeError, UnicodeError, ValueError, yaml.YAMLError):
        raise ApplyError("could not reconcile Hermes 1Password configuration") from None


def validate_onepassword_configurations(
    manifest: BootstrapManifest,
    targets: Sequence[tuple[str, Path]],
) -> None:
    """Verify every managed 1Password reference was installed as declared."""

    if not manifest.onepassword_items:
        return
    data_root = targets[0][1] if targets else None
    try:
        if data_root is None:
            raise ValueError
        state_names = _read_managed_environment_state(data_root)
        expected_state_names = {
            environment_name
            for profile, _target in targets
            for environment_name, _item, _field in managed_environment_bindings(
                manifest, profile
            )
        }
        if state_names != expected_state_names:
            raise ValueError
        for profile, target in targets:
            path = target / "config.yaml"
            metadata = path.lstat()
            if (
                stat.S_ISLNK(metadata.st_mode)
                or not stat.S_ISREG(metadata.st_mode)
                or metadata.st_nlink != 1
            ):
                raise ValueError
            config = yaml.safe_load(path.read_text(encoding="utf-8"))
            if not isinstance(config, dict):
                raise ValueError
            secrets = config.get("secrets")
            onepassword = secrets.get("onepassword") if isinstance(secrets, dict) else None
            if not isinstance(onepassword, dict):
                raise ValueError
            expected = build_onepassword_config(manifest, profile)
            for key in ("enabled", "account", "service_account_token_env", "binary_path"):
                if onepassword.get(key) != expected[key]:
                    raise ValueError
            installed_env = onepassword.get("env")
            expected_env = expected["env"]
            if not isinstance(installed_env, dict) or not isinstance(expected_env, dict):
                raise ValueError
            if any(key in installed_env for key in expected_env):
                raise ValueError
    except (OSError, TypeError, UnicodeError, ValueError, yaml.YAMLError):
        raise ApplyError("installed Hermes 1Password configuration is invalid") from None


def _read_managed_environment_state(data_root: Path) -> set[str]:
    """Read the previous manifest-owned environment names, failing closed."""

    path = data_root / _MANAGED_ENVIRONMENT_STATE
    try:
        metadata = path.lstat()
    except FileNotFoundError:
        return set()
    except OSError:
        raise ApplyError("managed Hermes environment state is unavailable") from None
    if (
        stat.S_ISLNK(metadata.st_mode)
        or not stat.S_ISREG(metadata.st_mode)
        or stat.S_IMODE(metadata.st_mode) != 0o600
    ):
        raise ApplyError("managed Hermes environment state is unsafe")
    try:
        state = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        raise ApplyError("managed Hermes environment state is invalid") from None
    if not isinstance(state, dict) or set(state) != {"schema_version", "environment_names"}:
        raise ApplyError("managed Hermes environment state is invalid")
    names = state["environment_names"]
    if (
        state["schema_version"] != 1
        or not isinstance(names, list)
        or any(not isinstance(name, str) or not name for name in names)
        or len(set(names)) != len(names)
    ):
        raise ApplyError("managed Hermes environment state is invalid")
    return set(names)
