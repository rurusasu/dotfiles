from __future__ import annotations

import io
import json
import sys
import unittest
from pathlib import Path
from unittest import mock


BOOTSTRAP_ROOT = Path(__file__).resolve().parents[3] / "scripts" / "python"
sys.path.insert(0, str(BOOTSTRAP_ROOT))

from hermes_bootstrap.errors import CredentialError, InputError, ValidationError
from hermes_bootstrap.manifest import load_manifest
from hermes_bootstrap.payload import (
    MAX_LINE_BYTES,
    MAX_TOTAL_BYTES,
    read_secret_payload,
)


REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
APPROVED_MANIFEST = REPOSITORY_ROOT / "nix/modules/ai_agents/hermes/manifest.yaml"


def raw_item(identifier: str, values: dict[str, str]) -> dict[str, object]:
    return {
        "id": identifier,
        "fields": [
            {"label": label, "value": value}
            for label, value in values.items()
        ],
    }


def secret_items() -> dict[str, dict[str, object]]:
    return {
        "github": raw_item("github-id", {"PAT": "github-token"}),
        "google_calendar": raw_item(
            "google-calendar-id",
            {
                "oauth credentials json": json.dumps(
                    {
                        "installed": {
                            "client_id": "calendar-client-id",
                            "client_secret": "calendar-client-secret",
                        }
                    }
                ),
                "tokens json": json.dumps(
                    {"accounts": {"shared": {"refresh_token": "calendar-refresh-token"}}}
                ),
            },
        ),
    }


def payload_stream(items: dict[str, object]) -> io.StringIO:
    records: list[dict[str, object]] = [{"type": "header", "schema_version": 1}]
    records.extend({"type": "item", "key": key, "item": item} for key, item in items.items())
    records.append({"type": "end"})
    return io.StringIO("".join(json.dumps(record, separators=(",", ":")) + "\n" for record in records))


class PayloadTests(unittest.TestCase):
    def setUp(self) -> None:
        self.manifest = load_manifest(APPROVED_MANIFEST)

    def assert_input_error(self, stream: io.IOBase) -> None:
        with self.assertRaises(InputError):
            read_secret_payload(stream, self.manifest)

    def test_invalid_google_calendar_json_is_rejected_without_leaking_values(self) -> None:
        items = secret_items()
        items["google_calendar"] = raw_item(
            "google-calendar-id",
            {
                "oauth_credentials_json": '{"installed":{"client_id":"secret-marker"}}',
                "tokens_json": '{"refresh_token":"calendar-refresh-token"}',
            },
        )

        with self.assertRaises(CredentialError) as caught:
            read_secret_payload(payload_stream(items), self.manifest)
        for marker in ("secret-marker", "calendar-refresh-token"):
            self.assertNotIn(marker, str(caught.exception))

    def test_each_declared_key_must_appear_once_and_no_other_key_is_accepted(self) -> None:
        duplicate = secret_items()
        records = [{"type": "header", "schema_version": 1}]
        records.extend({"type": "item", "key": key, "item": item} for key, item in duplicate.items())
        records.append({"type": "item", "key": "github", "item": duplicate["github"]})
        records.append({"type": "end"})
        self.assert_input_error(io.StringIO("".join(json.dumps(record) + "\n" for record in records)))

        undeclared = secret_items()
        undeclared["not-declared"] = raw_item("unknown", {"credential": "must-not-leak"})
        self.assert_input_error(payload_stream(undeclared))

        missing = secret_items()
        del missing["github"]
        self.assert_input_error(payload_stream(missing))

    def test_invalid_utf8_and_json_errors_hide_payload_values(self) -> None:
        for stream, marker in (
            (io.BytesIO(b'{"type":"header","schema_version":1}\nutf8-trace-marker\xff\n'), "utf8-trace-marker"),
            (io.StringIO('{"type":"header","schema_version":1}\n{json-trace-marker\n'), "json-trace-marker"),
        ):
            with self.subTest(stream=type(stream).__name__):
                with self.assertRaises(InputError) as caught:
                    read_secret_payload(stream, self.manifest)
                self.assertNotIn(marker, str(caught.exception))

    def test_item_validation_errors_hide_raw_item_values(self) -> None:
        malformed = secret_items()
        malformed["github"] = {"id": "malformed-id-marker", "fields": "malformed-secret-marker"}
        duplicate = secret_items()
        duplicate["github"] = raw_item(
            "duplicate-id-marker", {"token": "duplicate-secret-one", "PAT": "duplicate-secret-two"}
        )
        missing = secret_items()
        missing["github"] = raw_item("missing-id-marker", {"other": "missing-secret-marker"})

        for items, expected_type, markers in (
            (malformed, ValidationError, ("malformed-id-marker", "malformed-secret-marker")),
            (duplicate, ValidationError, ("duplicate-id-marker", "duplicate-secret-one", "duplicate-secret-two")),
            (missing, CredentialError, ("missing-id-marker", "missing-secret-marker")),
        ):
            with self.subTest(expected_type=expected_type.__name__):
                with self.assertRaises(expected_type) as caught:
                    read_secret_payload(payload_stream(items), self.manifest)
                for marker in markers:
                    self.assertNotIn(marker, str(caught.exception))

    def test_line_and_total_size_limits_are_checked_before_unbounded_decoding(self) -> None:
        overlong = b"x" * (MAX_LINE_BYTES + 1) + b"\n"
        self.assert_input_error(io.BytesIO(overlong))

        stream = payload_stream(secret_items())
        size = len(stream.getvalue().encode("utf-8"))
        self.assertLess(size, MAX_TOTAL_BYTES)
        with mock.patch("hermes_bootstrap.payload.MAX_TOTAL_BYTES", size - 1):
            self.assert_input_error(stream)

    def test_parsed_secrets_are_hidden_from_representations(self) -> None:
        secrets = read_secret_payload(payload_stream(secret_items()), self.manifest)
        values = (
            secrets.github_token,
            secrets.google_calendar.oauth_credentials_json,
            secrets.google_calendar.tokens_json,
        )

        for value in values:
            self.assertNotIn(value, repr(secrets))
            self.assertNotIn(value, repr(secrets.google_calendar))


if __name__ == "__main__":
    unittest.main()
