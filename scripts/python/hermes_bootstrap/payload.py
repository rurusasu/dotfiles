"""Bounded 1Password payload handling for Hermes bootstrap."""

from __future__ import annotations

import json
from collections.abc import Mapping
from dataclasses import dataclass
from typing import BinaryIO, TextIO

from .errors import CredentialError, InputError, ValidationError
from .models import BootstrapManifest, OnePasswordItem


SCHEMA_VERSION = 1
MAX_LINE_BYTES = 1024 * 1024
MAX_TOTAL_BYTES = 8 * 1024 * 1024
_BOOTSTRAP_ITEM_KEYS = frozenset({"github", "google_calendar"})


@dataclass(frozen=True, repr=False)
class GoogleCalendarSecret:
    oauth_credentials_json: str
    tokens_json: str

    def __repr__(self) -> str:
        return "GoogleCalendarSecret(<redacted>)"


@dataclass(frozen=True, repr=False)
class SecretBundle:
    github_token: str
    google_calendar: GoogleCalendarSecret

    def __repr__(self) -> str:
        return "SecretBundle(<redacted>)"


def build_secret_plan(manifest: BootstrapManifest) -> dict[str, object]:
    """Plan only the item lookups needed by bootstrap itself."""

    return {
        "schema_version": SCHEMA_VERSION,
        "items": [
            {
                "key": item.key,
                "account": item.account,
                "vault": item.vault,
                "item": item.item,
            }
            for item in _bootstrap_secret_items(manifest)
        ],
    }


def read_secret_payload(stream: TextIO, manifest: BootstrapManifest) -> SecretBundle:
    """Read bounded NDJSON from stdin and extract typed secrets."""

    declared = {item.key: item for item in _bootstrap_secret_items(manifest)}
    parsed: dict[str, dict[str, str]] = {}
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
        key, fields = _parse_item_record(record, declared)
        if key in parsed:
            raise InputError("secret payload contains a duplicate item key")
        parsed[key] = fields

    if set(parsed) != set(declared):
        raise InputError("secret payload does not contain every declared item")
    if _read_record(reader, total_bytes) is not None:
        raise InputError("secret payload contains a trailing record")

    return _bundle_from_fields(parsed)


def _bootstrap_secret_items(manifest: BootstrapManifest) -> tuple[OnePasswordItem, ...]:
    items = tuple(
        item for item in manifest.onepassword_items if item.key in _BOOTSTRAP_ITEM_KEYS
    )
    if {item.key for item in items} != _BOOTSTRAP_ITEM_KEYS:
        raise ValidationError("manifest is missing a required Hermes credential declaration")
    return items


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
            raise InputError("secret payload is not valid UTF-8") from None
    elif isinstance(line, str):
        try:
            size = len(line.encode("utf-8"))
        except UnicodeEncodeError:
            raise InputError("secret payload is not valid UTF-8") from None
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
    except (TypeError, ValueError):
        raise InputError("secret payload contains invalid JSON") from None
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
) -> tuple[str, dict[str, str]]:
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
    for raw_field in fields:
        if not isinstance(raw_field, dict):
            raise ValidationError("secret payload item field is invalid")
        field_id = raw_field.get("id")
        label = raw_field.get("label")
        value = raw_field.get("value")
        if (field_id is not None and not isinstance(field_id, str)) or not isinstance(label, str):
            raise ValidationError("secret payload item field is invalid")
        matches = set(aliases.get(_normalize_label(label), ()))
        if field_id:
            matches.update(aliases.get(_normalize_label(field_id), ()))
        if len(matches) > 1:
            raise ValidationError("secret payload item field label is ambiguous")
        if value is None:
            continue
        if not isinstance(value, str):
            raise ValidationError("secret payload item field is invalid")
        if matches:
            extracted[next(iter(matches))].append(value)

    result: dict[str, str] = {}
    for canonical_name, values in extracted.items():
        if not values or not values[0]:
            raise CredentialError("secret payload is missing a required credential field")
        if len(values) != 1:
            raise ValidationError("secret payload contains duplicate matching credential fields")
        result[canonical_name] = values[0]
    return key, result


def _field_aliases(item: OnePasswordItem) -> dict[str, tuple[str, ...]]:
    aliases: dict[str, set[str]] = {}
    for field in item.fields:
        for label in field.labels:
            aliases.setdefault(_normalize_label(label), set()).add(field.canonical_name)
    return {label: tuple(sorted(names)) for label, names in aliases.items()}


def _normalize_label(label: str) -> str:
    return "".join(character for character in label.casefold() if character not in " -_")


def _bundle_from_fields(parsed: Mapping[str, Mapping[str, str]]) -> SecretBundle:
    try:
        github_token = parsed["github"]["credential"]
        calendar_fields = parsed["google_calendar"]
        google_calendar = GoogleCalendarSecret(
            oauth_credentials_json=calendar_fields["oauth_credentials_json"],
            tokens_json=calendar_fields["tokens_json"],
        )
    except KeyError as error:
        raise ValidationError("manifest is missing a required Hermes credential declaration") from error
    validate_google_calendar_secret(google_calendar)

    return SecretBundle(
        github_token=github_token,
        google_calendar=google_calendar,
    )


def validate_google_calendar_secret(secret: GoogleCalendarSecret) -> None:
    validate_google_oauth_client(secret.oauth_credentials_json)
    try:
        tokens = json.loads(secret.tokens_json)
    except (TypeError, ValueError):
        raise CredentialError("Google Calendar credentials are invalid") from None
    if not isinstance(tokens, dict) or not _contains_refresh_token(tokens):
        raise CredentialError("Google Calendar credentials are invalid") from None


def validate_google_oauth_client(credentials_json: str) -> None:
    """Validate the OAuth client shared by Calendar and Gmail."""

    try:
        oauth = json.loads(credentials_json)
        installed = oauth["installed"]
        client_id = installed["client_id"]
        client_secret = installed["client_secret"]
    except (KeyError, TypeError, ValueError):
        raise CredentialError("Google Calendar credentials are invalid") from None
    if (
        not isinstance(oauth, dict)
        or not isinstance(installed, dict)
        or not isinstance(client_id, str)
        or not client_id
        or not isinstance(client_secret, str)
        or not client_secret
    ):
        raise CredentialError("Google Calendar credentials are invalid") from None


def _contains_refresh_token(value: object) -> bool:
    if isinstance(value, dict):
        refresh_token = value.get("refresh_token")
        if isinstance(refresh_token, str) and refresh_token:
            return True
        return any(_contains_refresh_token(child) for child in value.values())
    if isinstance(value, list):
        return any(_contains_refresh_token(child) for child in value)
    return False


def _exact_keys(record: Mapping[str, object], expected: set[str], context: str) -> None:
    if set(record) != expected:
        raise InputError(f"secret payload {context} record has an invalid shape")
