from __future__ import annotations

import base64
import io
import json
import sys
import unittest
from dataclasses import FrozenInstanceError, replace
from pathlib import Path
from types import MappingProxyType


BOOTSTRAP_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BOOTSTRAP_ROOT))

from hermes_bootstrap.errors import CredentialError, InputError, ValidationError
from hermes_bootstrap.manifest import load_manifest
from hermes_bootstrap.models import OnePasswordField, OnePasswordItem
from hermes_bootstrap.payload import (
    MAX_LINE_BYTES,
    MAX_TOTAL_BYTES,
    DashboardSecret,
    SecretRedactor,
    SlackSecret,
    build_secret_plan,
    read_secret_payload,
)


REPOSITORY_ROOT = Path(__file__).resolve().parents[4]
APPROVED_MANIFEST = REPOSITORY_ROOT / "docker/hermes-agent/bootstrap-manifest.yaml"


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
        "dashboard": raw_item("dashboard-id", {"user name": "dash-user", "PASSWORD": "dash-pass"}),
        "github": raw_item("github-id", {"PAT": "github-token"}),
        "slack_default": raw_item(
            "slack-default-id",
            {"bot token": "xoxb-default", "app-level token": "xapp-default", "allow_from": "UDEFAULT"},
        ),
        "slack_rick": raw_item(
            "slack-rick-id",
            {"SLACK_BOT_TOKEN": "xoxb-rick", "app token": "xapp-rick", "allowed users": "URICK"},
        ),
        "slack_hoffman": raw_item(
            "slack-hoffman-id",
            {"bot_token": "xoxb-hoffman", "app_token": "xapp-hoffman", "allowed_users": "UHOFFMAN"},
        ),
        "slack_risarisa": raw_item(
            "slack-risarisa-id",
            {"bot_token": "xoxb-risarisa", "app_token": "xapp-risarisa", "allowed_users": "URISARISA"},
        ),
    }


def payload_stream(items: dict[str, object], *, include_end: bool = True) -> io.StringIO:
    records: list[dict[str, object]] = [{"type": "header", "schema_version": 1}]
    records.extend({"type": "item", "key": key, "item": item} for key, item in items.items())
    if include_end:
        records.append({"type": "end"})
    return io.StringIO("".join(json.dumps(record, separators=(",", ":")) + "\n" for record in records))


class PayloadTests(unittest.TestCase):
    def setUp(self) -> None:
        self.manifest = load_manifest(APPROVED_MANIFEST)

    def assert_input_error(self, stream: io.IOBase) -> None:
        with self.assertRaises(InputError):
            read_secret_payload(stream, self.manifest)

    def test_build_secret_plan_is_exact_ordered_non_secret_metadata(self) -> None:
        self.assertEqual(
            build_secret_plan(self.manifest),
            {
                "schema_version": 1,
                "items": [
                    {
                        "key": "dashboard",
                        "account": "my.1password.com",
                        "vault": "openclaw",
                        "item": "Hermes Agent Dashboard",
                        "fields": [
                            {"canonical_name": "username", "labels": ["username", "user name"]},
                            {"canonical_name": "password", "labels": ["password"]},
                        ],
                    },
                    {
                        "key": "github",
                        "account": "my.1password.com",
                        "vault": "openclaw",
                        "item": "GitHubUsedOpenClawPAT",
                        "fields": [
                            {"canonical_name": "credential", "labels": ["credential", "token", "PAT", "password"]}
                        ],
                    },
                    *[
                        {
                            "key": key,
                            "account": "my.1password.com",
                            "vault": "openclaw",
                            "item": item,
                            "fields": [
                                {"canonical_name": "bot_token", "labels": ["SLACK_BOT_TOKEN", "bot_token", "bot token"]},
                                {"canonical_name": "app_token", "labels": ["SLACK_APP_TOKEN", "app_level_token", "app token", "app-level token"]},
                                {"canonical_name": "allowed_users", "labels": ["SLACK_ALLOWED_USERS", "allowed_users", "allowed users", "allowFrom", "allow_from"]},
                            ],
                        }
                        for key, item in (
                            ("slack_default", "SlackBot-OpenClaw"),
                            ("slack_rick", "SlackBot-Rick"),
                            ("slack_hoffman", "SlackBot-Hoffman"),
                            ("slack_risarisa", "SlackBot-Risarisa"),
                        )
                    ],
                ],
            },
        )

    def test_valid_payload_returns_immutable_typed_secrets(self) -> None:
        secrets = read_secret_payload(payload_stream(secret_items()), self.manifest)

        self.assertEqual(secrets.github_token, "github-token")
        self.assertEqual(secrets.dashboard, DashboardSecret(username="dash-user", password="dash-pass"))
        self.assertEqual(secrets.slack_by_profile["rick"], SlackSecret("xoxb-rick", "xapp-rick", "URICK"))
        self.assertIsInstance(secrets.slack_by_profile, MappingProxyType)
        with self.assertRaises(TypeError):
            secrets.slack_by_profile["rick"] = SlackSecret("a", "b", "c")
        with self.assertRaises(FrozenInstanceError):
            secrets.github_token = "changed"

    def test_header_and_end_records_are_required_with_no_trailing_record(self) -> None:
        self.assert_input_error(io.StringIO(json.dumps({"type": "item", "key": "github", "item": {}}) + "\n"))
        self.assert_input_error(payload_stream(secret_items(), include_end=False))

        stream = payload_stream(secret_items())
        stream.seek(0, io.SEEK_END)
        stream.write(json.dumps({"type": "end"}) + "\n")
        stream.seek(0)
        self.assert_input_error(stream)

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

    def test_invalid_utf8_json_and_record_shape_are_stable_input_errors_without_payload_echo(self) -> None:
        for stream in (
            io.TextIOWrapper(io.BytesIO(b'{"type":"header","schema_version":1}\n\xff\n'), encoding="utf-8"),
            io.StringIO('{"type":"header","schema_version":1}\n{not json secret-contents}\n'),
            io.StringIO('{"type":"header","schema_version":1}\n["secret-contents"]\n'),
        ):
            with self.subTest(stream=type(stream).__name__):
                with self.assertRaises(InputError) as caught:
                    read_secret_payload(stream, self.manifest)
                self.assertNotIn("secret-contents", str(caught.exception))

    def test_missing_or_ambiguous_required_fields_are_safe_credential_or_validation_errors(self) -> None:
        missing = secret_items()
        missing["github"] = raw_item("github-id", {"other": "missing-secret"})
        with self.assertRaises(CredentialError) as caught:
            read_secret_payload(payload_stream(missing), self.manifest)
        self.assertNotIn("missing-secret", str(caught.exception))

        ambiguous = secret_items()
        ambiguous["github"] = raw_item(
            "github-id",
            {"token": "first-secret", "PAT": "second-secret"},
        )
        with self.assertRaises(ValidationError) as caught:
            read_secret_payload(payload_stream(ambiguous), self.manifest)
        self.assertNotIn("first-secret", str(caught.exception))
        self.assertNotIn("second-secret", str(caught.exception))

    def test_label_normalization_is_case_insensitive_and_ignores_spaces_hyphens_and_underscores(self) -> None:
        normalized = secret_items()
        normalized["slack_default"] = raw_item(
            "slack-default-id",
            {"sLaCk BoT-tOkEn": "xoxb-default", "slack_app token": "xapp-default", "ALLOWED USERS": "UDEFAULT"},
        )

        secrets = read_secret_payload(payload_stream(normalized), self.manifest)

        self.assertEqual(secrets.slack_by_profile["default"], SlackSecret("xoxb-default", "xapp-default", "UDEFAULT"))

    def test_line_and_total_size_limits_are_checked_before_unbounded_decoding(self) -> None:
        overlong = b"x" * (MAX_LINE_BYTES + 1) + b"\n"
        self.assert_input_error(io.BytesIO(overlong))

        extra_items = tuple(
            OnePasswordItem(
                key=f"extra_{number}",
                account="my.1password.com",
                vault="openclaw",
                item=f"Extra {number}",
                fields=(OnePasswordField(canonical_name="credential", labels=("credential",)),),
            )
            for number in range(3)
        )
        expanded_manifest = replace(self.manifest, onepassword_items=self.manifest.onepassword_items + extra_items)
        oversized_items = secret_items()
        padding = "x" * (MAX_LINE_BYTES - 512)
        for item in oversized_items.values():
            item["padding"] = padding
        for number in range(3):
            oversized_items[f"extra_{number}"] = raw_item(
                f"extra-{number}", {"credential": f"extra-secret-{number}"}
            )
            oversized_items[f"extra_{number}"]["padding"] = padding
        stream = payload_stream(oversized_items)
        self.assertGreater(len(stream.getvalue().encode("utf-8")), MAX_TOTAL_BYTES)
        with self.assertRaises(InputError):
            read_secret_payload(stream, expanded_manifest)

    def test_secret_redactor_covers_raw_url_bearer_and_basic_derivatives_without_repr_leaks(self) -> None:
        secrets = read_secret_payload(payload_stream(secret_items()), self.manifest)
        redactor = secrets.redactor
        basic = base64.b64encode(b"dash-user:dash-pass").decode("ascii")
        summary = (
            "github-token https://dash-user:dash-pass@example.test "
            "Bearer github-token Basic " + basic
        )

        redacted = redactor.redact(summary)

        for secret in ("github-token", "dash-user", "dash-pass", basic):
            self.assertNotIn(secret, redacted)
            self.assertNotIn(secret, repr(redactor))
            self.assertNotIn(secret, repr(secrets))
        self.assertIn("[REDACTED]", redacted)
        self.assertEqual(redactor.redact("plain text"), "plain text")
        self.assertIsInstance(redactor, SecretRedactor)


if __name__ == "__main__":
    unittest.main()
