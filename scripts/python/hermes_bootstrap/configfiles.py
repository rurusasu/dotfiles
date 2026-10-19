"""Reconcile managed Hermes configuration sections with atomic file writes."""

from __future__ import annotations

import stat
from collections.abc import Sequence
from pathlib import Path

import yaml

from .distributions import _atomic_write
from .errors import ApplyError
from .mcp_config import install_mcp_configurations, load_managed_config
from .models import BootstrapManifest
from .onepassword import build_onepassword_config, managed_environment_bindings

_XAPI_MCP = {
    "url": "http://127.0.0.1:8766/mcp",
    "connect_timeout": 300,
}
_CHROME_MCP = {
    "url": "http://127.0.0.1:8765/mcp",
    "connect_timeout": 120,
}


def reconcile_xapi_configurations(
    targets: Sequence[Path],
) -> None:
    """Install the canonical internal X API MCP in every runtime profile."""

    _reconcile_mcp_configurations(targets, "xapi", _XAPI_MCP, "X API")


def validate_xapi_configurations(targets: Sequence[Path]) -> None:
    """Require the canonical internal X API MCP in every runtime profile."""

    _validate_mcp_configurations(targets, "xapi", _XAPI_MCP, "X API")


def reconcile_chrome_configurations(
    targets: Sequence[Path],
) -> None:
    """Point each Hermes profile at the host-published browser MCP endpoint."""

    _reconcile_mcp_configurations(
        targets, "chrome", _CHROME_MCP, "browser MCP"
    )


def validate_chrome_configurations(targets: Sequence[Path]) -> None:
    """Require each profile's browser MCP URL to be reachable from native Hermes."""

    _validate_mcp_configurations(targets, "chrome", _CHROME_MCP, "browser MCP")


def _reconcile_mcp_configurations(
    targets: Sequence[Path],
    name: str,
    configuration: dict[str, object],
    label: str,
) -> None:
    try:
        install_mcp_configurations(
            targets,
            name,
            configuration,
            skip_invalid=False,
            create_servers=True,
        )
    except (OSError, TypeError, UnicodeError, ValueError, yaml.YAMLError):
        raise ApplyError(f"could not reconcile Hermes {label} configuration") from None


def _validate_mcp_configurations(
    targets: Sequence[Path],
    name: str,
    configuration: dict[str, object],
    label: str,
) -> None:
    try:
        for target in targets:
            candidate = load_managed_config(target / "config.yaml")
            if candidate is None or candidate[2].get(name) != configuration:
                raise ValueError
    except (OSError, TypeError, UnicodeError, ValueError, yaml.YAMLError):
        raise ApplyError(f"installed Hermes {label} configuration is invalid") from None


def reconcile_onepassword_cli_permissions(
    data_root: Path,
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

    try:
        path.chmod(0o700)
    except (OSError, ValueError):
        raise ApplyError("could not secure 1Password CLI configuration") from None


def reconcile_onepassword_configurations(
    manifest: BootstrapManifest,
    targets: Sequence[tuple[str, Path]],
) -> None:
    """Merge managed onepassword settings into each Hermes config atomically."""

    if not manifest.onepassword_items:
        return

    try:
        if not targets:
            raise ApplyError("managed Hermes configuration targets are empty")
        managed_names = {
            environment_name
            for profile, _target in targets
            for environment_name, _item, _field in managed_environment_bindings(
                manifest, profile
            )
        }
        for profile, target in targets:
            path = target / "config.yaml"
            try:
                metadata = path.lstat()
            except OSError:
                raise ApplyError(
                    "managed Hermes configuration is unavailable"
                ) from None
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
                if key not in managed_names
                and not (
                    key == "HERMES_DASHBOARD_BASIC_AUTH_USERNAME"
                    and value == "op://openclaw/Hermes Agent Dashboard/username"
                )
            }
            managed_config = build_onepassword_config(manifest, profile)
            managed_env = managed_config["env"]
            if not isinstance(managed_env, dict):
                raise ApplyError("managed Hermes 1Password environment is invalid")
            managed_platforms = None
            if "DISCORD_BOT_TOKEN" in managed_env:
                platforms = config.get("platforms", {})
                if not isinstance(platforms, dict):
                    raise ApplyError("managed Hermes platform configuration is invalid")
                discord = platforms.get("discord", {})
                if not isinstance(discord, dict):
                    raise ApplyError("managed Hermes Discord configuration is invalid")
                extra = discord.get("extra", {})
                if not isinstance(extra, dict):
                    raise ApplyError("managed Hermes Discord configuration is invalid")
                managed_discord = dict(discord) | {"allow_bots": "mentions"}
                if "allow_bots" in extra:
                    retained_extra = dict(extra)
                    retained_extra.pop("allow_bots")
                    if retained_extra:
                        managed_discord["extra"] = retained_extra
                    else:
                        managed_discord.pop("extra")
                managed_platforms = dict(platforms)
                managed_platforms["discord"] = managed_discord

            if "secrets" not in config and (
                "platforms" not in config or managed_platforms is None
            ):
                additions = {"secrets": {"onepassword": managed_config}}
                if managed_platforms is not None:
                    additions["platforms"] = managed_platforms
                content = (
                    original_content.rstrip("\n")
                    + "\n"
                    + yaml.safe_dump(additions, sort_keys=False)
                ).encode("utf-8")
                _atomic_write(path, content, stat.S_IMODE(metadata.st_mode))
                continue
            if onepassword == managed_config and (
                managed_platforms is None or managed_platforms == config.get("platforms")
            ):
                continue
            merged_onepassword = dict(onepassword)
            merged_onepassword.update(managed_config)
            merged_onepassword["env"] = retained_env | managed_env
            merged_secrets = dict(secrets)
            merged_secrets["onepassword"] = merged_onepassword
            candidate = dict(config)
            candidate["secrets"] = merged_secrets
            if managed_platforms is not None:
                candidate["platforms"] = managed_platforms
            content = yaml.safe_dump(candidate, sort_keys=False).encode("utf-8")
            if original_content.encode("utf-8") == content:
                continue
            _atomic_write(path, content, stat.S_IMODE(metadata.st_mode))
    except (OSError, TypeError, UnicodeError, ValueError, yaml.YAMLError):
        raise ApplyError("could not reconcile Hermes 1Password configuration") from None


def validate_onepassword_configurations(
    manifest: BootstrapManifest,
    targets: Sequence[tuple[str, Path]],
) -> None:
    """Verify every managed 1Password reference was installed as declared."""

    if not manifest.onepassword_items:
        return
    try:
        if not targets:
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
                raise TypeError
            secrets = config.get("secrets")
            onepassword = (
                secrets.get("onepassword") if isinstance(secrets, dict) else None
            )
            if not isinstance(onepassword, dict):
                raise TypeError
            expected = build_onepassword_config(manifest, profile)
            for key in (
                "enabled",
                "account",
                "service_account_token_env",
                "binary_path",
            ):
                if onepassword.get(key) != expected[key]:
                    raise ValueError
            installed_env = onepassword.get("env")
            expected_env = expected["env"]
            if not isinstance(installed_env, dict) or not isinstance(
                expected_env, dict
            ):
                raise TypeError
            if any(installed_env.get(key) != value for key, value in expected_env.items()):
                raise ValueError
            if "DISCORD_BOT_TOKEN" in expected_env:
                platforms = config.get("platforms")
                discord = platforms.get("discord") if isinstance(platforms, dict) else None
                if not isinstance(discord, dict) or discord.get("allow_bots") != "mentions":
                    raise ValueError
                extra = discord.get("extra", {})
                if not isinstance(extra, dict) or extra.get("allow_bots", "mentions") != "mentions":
                    raise ValueError
    except (OSError, TypeError, UnicodeError, ValueError, yaml.YAMLError):
        raise ApplyError(
            "installed Hermes 1Password configuration is invalid"
        ) from None
