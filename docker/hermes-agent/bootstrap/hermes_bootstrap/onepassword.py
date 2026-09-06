"""Build the managed Hermes 1Password configuration without secret values."""

from __future__ import annotations

from .errors import ValidationError
from .models import BootstrapManifest, OnePasswordField, OnePasswordItem


_SERVICE_ACCOUNT_ENV = "OP_SERVICE_ACCOUNT_TOKEN"
_OP_BINARY = "/usr/bin/op"
def managed_environment_bindings(
    manifest: BootstrapManifest, profile: str
) -> tuple[tuple[str, OnePasswordItem, OnePasswordField], ...]:
    """Return manifest-declared environment bindings for one profile."""

    bindings: list[tuple[str, OnePasswordItem, OnePasswordField]] = []
    seen: set[str] = set()
    for item in manifest.onepassword_items:
        if item.profiles is not None and profile not in item.profiles:
            continue
        for field in item.fields:
            for environment_name in field.environment_names:
                if environment_name in seen:
                    raise ValidationError(
                        "1Password manifest has duplicate managed environment names"
                    )
                seen.add(environment_name)
                bindings.append((environment_name, item, field))
    return tuple(bindings)


def build_onepassword_config(
    manifest: BootstrapManifest, profile: str
) -> dict[str, object]:
    """Return the non-secret onepassword block for one Hermes home."""

    bindings = managed_environment_bindings(manifest, profile)
    accounts = {item.account for item in manifest.onepassword_items}
    if not accounts:
        raise ValidationError("1Password manifest has no managed items")
    if len(accounts) != 1:
        raise ValidationError("managed 1Password items use different accounts")
    account = next(iter(accounts))

    environment = {
        environment_name: _reference(item, field)
        for environment_name, item, field in bindings
    }

    return {
        "enabled": True,
        "env": environment,
        "account": account,
        "service_account_token_env": _SERVICE_ACCOUNT_ENV,
        "binary_path": _OP_BINARY,
        "cache_ttl_seconds": 300,
        "override_existing": True,
    }


def _reference(item: OnePasswordItem, field: OnePasswordField) -> str:
    reference_name = field.reference_name or field.canonical_name
    return f"op://{item.vault}/{item.item}/{reference_name}"
