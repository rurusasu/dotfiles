"""Versioned, redacted 1Password payload handling for Hermes bootstrap."""

from __future__ import annotations

import base64
import json
from collections.abc import Mapping
from dataclasses import dataclass
from typing import BinaryIO, TextIO
from types import MappingProxyType
from urllib.parse import quote

from .errors import CredentialError, InputError, ValidationError
from .models import BootstrapManifest, OnePasswordItem


SCHEMA_VERSION = 1
MAX_LINE_BYTES = 1024 * 1024
MAX_TOTAL_BYTES = 8 * 1024 * 1024
_REDACTED = "[REDACTED]"


@dataclass(frozen=True, repr=False)
class SlackSecret:
    bot_token: str
    app_token: str
    allowed_users: str

    def __repr__(self) -> str:
        return "SlackSecret(<redacted>)"


@dataclass(frozen=True, repr=False)
class DashboardSecret:
    username: str
    password: str

    def __repr__(self) -> str:
        return "DashboardSecret(<redacted>)"


@dataclass(frozen=True, repr=False)
class SecretBundle:
    github_token: str
    dashboard: DashboardSecret
    slack_by_profile: Mapping[str, SlackSecret]
    redactor: "SecretRedactor"

    def __repr__(self) -> str:
        return "SecretBundle(<redacted>)"


class SecretRedactor:
    """Redact all parsed secret values and credential encodings from text."""

    def __init__(
        self,
        values: tuple[str, ...],
        basic_credentials: tuple[tuple[str, str], ...] = (),
    ) -> None:
        replacements = {value for value in values if value}
        for value in tuple(replacements):
            replacements.add(quote(value, safe=""))
            replacements.add(f"Bearer {value}")
            replacements.add(f"bearer {value}")
        for username, password in basic_credentials:
            raw = f"{username}:{password}"
            encoded = base64.b64encode(raw.encode("utf-8")).decode("ascii")
            quoted_username = quote(username, safe="")
            quoted_password = quote(password, safe="")
            replacements.update(
                {
                    raw,
                    encoded,
                    f"Basic {encoded}",
                    f"basic {encoded}",
                    f"://{username}:{password}@",
                    f"://{quoted_username}:{quoted_password}@",
                }
            )
        self._replacements = tuple(sorted(replacements, key=len, reverse=True))

    def redact(self, text: str) -> str:
        """Return text suitable for exceptions and command summaries."""

        return _replace_all(text, self._replacements)

    def __repr__(self) -> str:
        return "SecretRedactor(<redacted>)"


def build_secret_plan(manifest: BootstrapManifest) -> dict[str, object]:
    """Build the deterministic, non-secret item lookup plan for host adapters."""

    return {
        "schema_version": SCHEMA_VERSION,
        "items": [
            {
                "key": item.key,
                "account": item.account,
                "vault": item.vault,
                "item": item.item,
                "fields": [
                    {
                        "canonical_name": field.canonical_name,
                        "labels": list(field.labels),
                    }
                    for field in item.fields
                ],
            }
            for item in manifest.onepassword_items
        ],
    }


def read_secret_payload(stream: TextIO, manifest: BootstrapManifest) -> SecretBundle:
    """Read bounded NDJSON from stdin and immediately extract typed secrets."""

    declared = {item.key: item for item in manifest.onepassword_items}
    parsed: dict[str, dict[str, str]] = {}
    discovered_values: list[str] = []
    reader = _binary_reader(stream)
    total_bytes = 0

    header = _read_record(reader, total_bytes)
    if header is None:
        raise InputError("secret payload is missing a header record")
    record, total_bytes = header
    _validate_header(record)

    while True:
        next_record = _read_record(reader, total_bytes)
        if next_record is None:
            raise InputError("secret payload is missing an end record")
        record, total_bytes = next_record
        record_type = _record_type(record)
        if record_type == "end":
            _validate_end(record)
            break
        if record_type != "item":
            raise InputError("secret payload contains an invalid record type")
        key, fields, values = _parse_item_record(record, declared)
        if key in parsed:
            raise InputError("secret payload contains a duplicate item key")
        parsed[key] = fields
        discovered_values.extend(values)

    if set(parsed) != set(declared):
        raise InputError("secret payload does not contain every declared item")
    if _read_record(reader, total_bytes) is not None:
        raise InputError("secret payload contains a trailing record")

    return _bundle_from_fields(manifest, parsed, tuple(discovered_values))


def _binary_reader(stream: TextIO) -> TextIO | BinaryIO:
    buffered = getattr(stream, "buffer", None)
    return buffered if buffered is not None else stream


def _read_record(reader: TextIO | BinaryIO, total_bytes: int) -> tuple[dict[str, object], int] | None:
    line = reader.readline(MAX_LINE_BYTES + 1)
    if not line:
        return None
    if isinstance(line, bytes):
        size = len(line)
        if size > MAX_LINE_BYTES:
            raise InputError("secret payload line exceeds the maximum size")
        total_bytes += size
        if total_bytes > MAX_TOTAL_BYTES:
            raise InputError("secret payload exceeds the maximum size")
        try:
            text = line.decode("utf-8")
        except UnicodeDecodeError:
            text = None
        if text is None:
            raise InputError("secret payload is not valid UTF-8")
    elif isinstance(line, str):
        try:
            size = len(line.encode("utf-8"))
        except UnicodeEncodeError:
            size = None
        if size is None:
            raise InputError("secret payload is not valid UTF-8")
        if size > MAX_LINE_BYTES:
            raise InputError("secret payload line exceeds the maximum size")
        total_bytes += size
        if total_bytes > MAX_TOTAL_BYTES:
            raise InputError("secret payload exceeds the maximum size")
        text = line
    else:
        raise InputError("secret payload stream is invalid")
    try:
        value = json.loads(text)
    except (TypeError, ValueError, json.JSONDecodeError):
        parsed_json = False
    else:
        parsed_json = True
    if not parsed_json:
        raise InputError("secret payload contains invalid JSON")
    if not isinstance(value, dict):
        raise InputError("secret payload record must be an object")
    return value, total_bytes


def _validate_header(record: dict[str, object]) -> None:
    _exact_keys(record, {"type", "schema_version"}, "header")
    if record.get("type") != "header":
        raise InputError("secret payload must start with a header record")
    schema_version = record.get("schema_version")
    if type(schema_version) is not int or schema_version != SCHEMA_VERSION:
        raise InputError("secret payload schema version is unsupported")


def _validate_end(record: dict[str, object]) -> None:
    _exact_keys(record, {"type"}, "end")


def _record_type(record: dict[str, object]) -> str:
    record_type = record.get("type")
    if not isinstance(record_type, str):
        raise InputError("secret payload record type is invalid")
    return record_type


def _parse_item_record(
    record: dict[str, object], declared: Mapping[str, OnePasswordItem]
) -> tuple[str, dict[str, str], tuple[str, ...]]:
    _exact_keys(record, {"type", "key", "item"}, "item")
    key = record.get("key")
    if not isinstance(key, str) or key not in declared:
        raise InputError("secret payload contains an undeclared item key")
    item = record.get("item")
    if not isinstance(item, dict):
        raise ValidationError("secret payload item must be an object")
    identifier = item.get("id")
    fields = item.get("fields")
    if not isinstance(identifier, str) or not identifier:
        raise ValidationError("secret payload item id is invalid")
    if not isinstance(fields, list):
        raise ValidationError("secret payload item fields are invalid")

    extracted: dict[str, list[str]] = {field.canonical_name: [] for field in declared[key].fields}
    aliases = _field_aliases(declared[key])
    discovered: list[str] = []
    for raw_field in fields:
        if not isinstance(raw_field, dict):
            raise ValidationError("secret payload item field is invalid")
        label = raw_field.get("label")
        value = raw_field.get("value")
        if not isinstance(label, str) or not isinstance(value, str):
            raise ValidationError("secret payload item field is invalid")
        discovered.append(value)
        matches = aliases.get(_normalize_label(label), ())
        if len(matches) > 1:
            raise ValidationError("secret payload item field label is ambiguous")
        if matches:
            extracted[matches[0]].append(value)

    result: dict[str, str] = {}
    for canonical_name, values in extracted.items():
        if not values or not values[0]:
            raise CredentialError("secret payload is missing a required credential field")
        if len(values) != 1:
            raise ValidationError("secret payload contains duplicate matching credential fields")
        result[canonical_name] = values[0]
    return key, result, tuple(discovered)


def _field_aliases(item: OnePasswordItem) -> dict[str, tuple[str, ...]]:
    aliases: dict[str, set[str]] = {}
    for field in item.fields:
        for label in field.labels:
            aliases.setdefault(_normalize_label(label), set()).add(field.canonical_name)
    return {label: tuple(sorted(names)) for label, names in aliases.items()}


def _normalize_label(label: str) -> str:
    return "".join(character for character in label.casefold() if character not in " -_")


def _bundle_from_fields(
    manifest: BootstrapManifest,
    parsed: Mapping[str, Mapping[str, str]],
    discovered_values: tuple[str, ...],
) -> SecretBundle:
    try:
        dashboard = DashboardSecret(
            username=parsed["dashboard"]["username"],
            password=parsed["dashboard"]["password"],
        )
        github_token = parsed["github"]["credential"]
    except KeyError as error:
        raise ValidationError("manifest is missing a required Hermes credential declaration") from error

    slack_by_profile: dict[str, SlackSecret] = {}
    required_profiles = ("default", *(profile.name for profile in manifest.profiles))
    for profile in required_profiles:
        key = f"slack_{profile}"
        try:
            fields = parsed[key]
            slack_by_profile[profile] = SlackSecret(
                bot_token=fields["bot_token"],
                app_token=fields["app_token"],
                allowed_users=fields["allowed_users"],
            )
        except KeyError as error:
            raise ValidationError("manifest is missing a required Slack credential declaration") from error

    redactor = SecretRedactor(
        discovered_values,
        basic_credentials=((dashboard.username, dashboard.password),),
    )
    return SecretBundle(
        github_token=github_token,
        dashboard=dashboard,
        slack_by_profile=MappingProxyType(slack_by_profile),
        redactor=redactor,
    )


def _exact_keys(record: Mapping[str, object], expected: set[str], context: str) -> None:
    if set(record) != expected:
        raise InputError(f"secret payload {context} record has an invalid shape")


def _replace_all(text: str, replacements: tuple[str, ...]) -> str:
    for replacement in replacements:
        if replacement:
            text = text.replace(replacement, _REDACTED)
    return text
