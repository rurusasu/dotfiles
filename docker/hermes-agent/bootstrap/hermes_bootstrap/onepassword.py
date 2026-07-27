"""Build the managed Hermes 1Password configuration without secret values."""

from __future__ import annotations

from .errors import ValidationError
from .models import BootstrapManifest, OnePasswordItem


_SERVICE_ACCOUNT_ENV = "OP_SERVICE_ACCOUNT_TOKEN"
_OP_BINARY = "/usr/bin/op"
_MANAGED_ENV_FIELDS: tuple[tuple[str, str, str], ...] = (
    ("HERMES_DASHBOARD_BASIC_AUTH_USERNAME", "dashboard", "username"),
    ("GITHUB_PERSONAL_ACCESS_TOKEN", "github", "credential"),
    ("GH_TOKEN", "github", "credential"),
    ("GITHUB_TOKEN", "github", "credential"),
)
_DISCORD_ENV_FIELDS: tuple[tuple[str, str], ...] = (
    ("DISCORD_BOT_TOKEN", "bot_token"),
    ("DISCORD_ALLOWED_USERS", "allowed_users"),
)


def build_onepassword_config(
    manifest: BootstrapManifest, profile: str
) -> dict[str, object]:
    """Return the non-secret onepassword block for one Hermes home."""

    items = {item.key: item for item in manifest.onepassword_items}
    discord_key = "discord_default" if profile == "default" else f"discord_{profile}"
    required = {key for _env, key, _field in _MANAGED_ENV_FIELDS}
    required.update({"dashboard", "github", discord_key})
    missing = sorted(key for key in required if key not in items)
    if missing:
        raise ValidationError("1Password manifest is missing managed items")

    managed_items = [items[key] for key in ("dashboard", "github", discord_key)]
    accounts = {item.account for item in managed_items}
    if len(accounts) != 1:
        raise ValidationError("managed 1Password items use different accounts")
    account = next(iter(accounts))

    environment: dict[str, str] = {}
    for env_name, item_key, field_name in _MANAGED_ENV_FIELDS:
        environment[env_name] = _reference(items[item_key], field_name)
    for env_name, field_name in _DISCORD_ENV_FIELDS:
        environment[env_name] = _reference(items[discord_key], field_name)

    return {
        "enabled": True,
        "env": environment,
        "account": account,
        "service_account_token_env": _SERVICE_ACCOUNT_ENV,
        "binary_path": _OP_BINARY,
        "cache_ttl_seconds": 300,
        "override_existing": True,
    }


def _reference(item: OnePasswordItem, canonical_name: str) -> str:
    fields = [field for field in item.fields if field.canonical_name == canonical_name]
    if len(fields) != 1:
        raise ValidationError("1Password manifest has an invalid managed field")
    field = fields[0]
    reference_name = field.reference_name or canonical_name
    return f"op://{item.vault}/{item.item}/{reference_name}"
