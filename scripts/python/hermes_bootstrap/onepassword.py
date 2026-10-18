"""Build native Hermes references and read bootstrap-only GitHub credentials."""

from __future__ import annotations

import os
import subprocess
from collections.abc import Mapping

from .errors import CredentialError, ValidationError
from .models import BootstrapManifest, OnePasswordField, OnePasswordItem


_SERVICE_ACCOUNT_ENV = "OP_SERVICE_ACCOUNT_TOKEN"
_OP_EXECUTABLE_ENV = "DOTFILES_HERMES_OP_EXECUTABLE"


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
        "binary_path": os.environ.get(_OP_EXECUTABLE_ENV, ""),
        "cache_ttl_seconds": 300,
        "override_existing": True,
    }


def read_github_token(
    manifest: BootstrapManifest, environ: Mapping[str, str]
) -> str:
    """Read the declared GitHub credential without exposing CLI output on failure."""

    items = [item for item in manifest.onepassword_items if item.key == "github"]
    if len(items) != 1:
        raise CredentialError("GitHub credentials are unavailable")
    item = items[0]
    fields = [field for field in item.fields if field.canonical_name == "credential"]
    if len(fields) != 1:
        raise CredentialError("GitHub credentials are unavailable")
    child_environment = dict(os.environ)
    child_environment.update(environ)
    executable = child_environment.get(_OP_EXECUTABLE_ENV) or "op"
    try:
        result = subprocess.run(
            [
                executable, "read", "--account", item.account, "--",
                _reference(item, fields[0]),
            ],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            env=child_environment,
            text=True,
            timeout=30,
            check=False,
        )
    except (OSError, ValueError, UnicodeError, subprocess.SubprocessError):
        raise CredentialError("GitHub credentials are unavailable") from None
    if result.returncode != 0:
        raise CredentialError("GitHub credentials are unavailable")
    token = result.stdout.removesuffix("\n").removesuffix("\r")
    if not token.strip() or any(character in token for character in ("\n", "\r", "\x00")):
        raise CredentialError("GitHub credentials are unavailable")
    return token


def _reference(item: OnePasswordItem, field: OnePasswordField) -> str:
    reference_name = field.reference_name or field.canonical_name
    return f"op://{item.vault}/{item.item}/{reference_name}"
