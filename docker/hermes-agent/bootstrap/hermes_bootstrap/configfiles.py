"""Transactional reconciliation of managed Hermes configuration sections."""

from __future__ import annotations

import stat
from collections.abc import Sequence
from pathlib import Path

import yaml

from .distributions import _atomic_write
from .envfiles import LEGACY_SLACK_KEYS
from .errors import ApplyError
from .models import BootstrapManifest
from .onepassword import build_onepassword_config
from .transaction import Transaction


def reconcile_onepassword_configurations(
    manifest: BootstrapManifest,
    targets: Sequence[tuple[str, Path]],
    transaction: Transaction,
) -> None:
    """Merge managed onepassword settings into each Hermes config atomically."""

    if not manifest.onepassword_items:
        return

    try:
        for profile, target in targets:
            path = target / "config.yaml"
            try:
                metadata = path.lstat()
            except OSError:
                continue
            if (
                stat.S_ISLNK(metadata.st_mode)
                or not stat.S_ISREG(metadata.st_mode)
                or metadata.st_nlink != 1
            ):
                continue
            try:
                original_content = path.read_text(encoding="utf-8")
            except (OSError, UnicodeError):
                continue
            try:
                config = yaml.safe_load(original_content)
            except (OSError, UnicodeError, yaml.YAMLError):
                continue
            if not isinstance(config, dict):
                continue

            secrets = config.get("secrets")
            if secrets is None:
                secrets = {}
            if not isinstance(secrets, dict):
                continue
            onepassword = secrets.get("onepassword")
            if onepassword is None:
                onepassword = {}
            if not isinstance(onepassword, dict):
                continue
            existing_env = onepassword.get("env")
            if existing_env is None:
                existing_env = {}
            if not isinstance(existing_env, dict):
                continue
            retained_env = {
                key: value
                for key, value in existing_env.items()
                if key not in LEGACY_SLACK_KEYS
            }

            managed = build_onepassword_config(manifest, profile)
            if "secrets" not in config:
                content = (
                    original_content.rstrip("\n")
                    + "\n"
                    + yaml.safe_dump(
                        {"secrets": {"onepassword": managed}},
                        sort_keys=False,
                    )
                ).encode("utf-8")
                if path.read_bytes() == content:
                    continue
                transaction.snapshot(path)
                _atomic_write(path, content, stat.S_IMODE(metadata.st_mode))
                continue
            if onepassword == managed and existing_env == managed["env"]:
                continue
            merged_onepassword = dict(onepassword)
            merged_onepassword.update(managed)
            merged_onepassword["env"] = {
                **retained_env,
                **managed["env"],
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
    except (OSError, TypeError, UnicodeError, ValueError, yaml.YAMLError):
        raise ApplyError("could not reconcile Hermes 1Password configuration") from None
