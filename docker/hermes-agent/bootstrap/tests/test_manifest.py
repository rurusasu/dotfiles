from __future__ import annotations

import json
import sys
import tempfile
import unittest
from dataclasses import FrozenInstanceError
from pathlib import Path


BOOTSTRAP_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BOOTSTRAP_ROOT))

from hermes_bootstrap.errors import (
    ApplyError,
    BootstrapError,
    CredentialError,
    InputError,
    MigrationError,
    RepositoryError,
    RollbackError,
    ValidationError,
)
from hermes_bootstrap.manifest import load_manifest


REPOSITORY_ROOT = Path(__file__).resolve().parents[4]
APPROVED_MANIFEST = REPOSITORY_ROOT / "docker/hermes-agent/bootstrap-manifest.yaml"


def manifest_data() -> dict[str, object]:
    return {
        "schema_version": 1,
        "data_root": "/opt/data",
        "onepassword_items": [
            {
                "key": "dashboard",
                "account": "my.1password.com",
                "vault": "openclaw",
                "item": "Hermes Agent Dashboard",
                "fields": [
                    {"canonical_name": "username", "labels": ["username", "user name"]},
                    {"canonical_name": "password", "labels": ["password"]},
                ],
            }
        ],
        "root_distribution": {
            "name": "default",
            "source": "https://github.com/rurusasu/hermes-home.git",
            "ref": "main",
            "target": "/opt/data",
            "manifest": "root-distribution.yaml",
        },
        "profiles": [
            {
                "name": "rick",
                "source": "https://github.com/rurusasu/hermes-profile-rick.git",
                "ref": "main",
                "target": "/opt/data/profiles/rick",
                "manifest": "distribution.yaml",
            }
        ],
        "shared_repositories": [
            {
                "name": "lifelog",
                "source": "https://github.com/rurusasu/lifelog.git",
                "ref": "main",
                "target": "/opt/data/shared/lifelog",
                "legacy_target": "/opt/data/core/lifelog",
                "mode": "read-write",
                "sync_owner": "default",
            }
        ],
    }


class ManifestTests(unittest.TestCase):
    def load_data(self, data: object):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "manifest.yaml"
            path.write_text(json.dumps(data), encoding="utf-8")
            return load_manifest(path)

    def assert_validation_error(self, data: object) -> None:
        with self.assertRaises(ValidationError):
            self.load_data(data)

    def test_approved_manifest_loads_all_targets(self) -> None:
        manifest = load_manifest(APPROVED_MANIFEST)

        self.assertEqual(manifest.schema_version, 1)
        self.assertEqual(manifest.data_root, Path("/opt/data"))
        self.assertEqual(manifest.root_distribution.name, "default")
        self.assertEqual(manifest.root_distribution.target, Path("/opt/data"))
        self.assertEqual(
            tuple(profile.name for profile in manifest.profiles),
            ("rick", "hoffman", "risarisa"),
        )
        self.assertEqual(
            tuple(profile.target for profile in manifest.profiles),
            (
                Path("/opt/data/profiles/rick"),
                Path("/opt/data/profiles/hoffman"),
                Path("/opt/data/profiles/risarisa"),
            ),
        )
        self.assertEqual(len(manifest.onepassword_items), 6)
        self.assertEqual(
            tuple(item.item for item in manifest.onepassword_items),
            (
                "Hermes Agent Dashboard",
                "GitHubUsedOpenClawPAT",
                "SlackBot-OpenClaw",
                "SlackBot-Rick",
                "SlackBot-Hoffman",
                "SlackBot-Risarisa",
            ),
        )
        self.assertEqual(manifest.shared_repositories[0].sync_owner, "default")
        self.assertEqual(manifest.shared_repositories[0].legacy_target, Path("/opt/data/core/lifelog"))
        with self.assertRaises(FrozenInstanceError):
            manifest.schema_version = 2

    def test_target_outside_data_root_is_rejected(self) -> None:
        data = manifest_data()
        data["profiles"][0]["target"] = "/opt/data/../outside"

        self.assert_validation_error(data)

    def test_read_write_repository_requires_sync_owner(self) -> None:
        data = manifest_data()
        del data["shared_repositories"][0]["sync_owner"]

        self.assert_validation_error(data)

    def test_missing_required_key_is_rejected(self) -> None:
        data = manifest_data()
        del data["root_distribution"]["source"]

        self.assert_validation_error(data)

    def test_unknown_key_is_rejected(self) -> None:
        data = manifest_data()
        data["profiles"][0]["unexpected"] = "value"

        self.assert_validation_error(data)

    def test_duplicate_names_are_rejected(self) -> None:
        data = manifest_data()
        data["profiles"].append(dict(data["profiles"][0]))

        self.assert_validation_error(data)

    def test_duplicate_target_names_are_rejected(self) -> None:
        data = manifest_data()
        duplicate = dict(data["profiles"][0])
        duplicate["name"] = "hoffman"
        data["profiles"].append(duplicate)

        self.assert_validation_error(data)

    def test_unsupported_schema_version_is_rejected(self) -> None:
        data = manifest_data()
        data["schema_version"] = 2

        self.assert_validation_error(data)

    def test_non_absolute_target_is_rejected(self) -> None:
        data = manifest_data()
        data["profiles"][0]["target"] = "profiles/rick"

        self.assert_validation_error(data)

    def test_invalid_ref_is_rejected(self) -> None:
        data = manifest_data()
        data["profiles"][0]["ref"] = "main^{commit}"

        self.assert_validation_error(data)

    def test_non_github_https_source_is_rejected(self) -> None:
        data = manifest_data()
        data["profiles"][0]["source"] = "git@github.com:rurusasu/hermes-profile-rick.git"

        self.assert_validation_error(data)

    def test_unsupported_shared_mode_is_rejected(self) -> None:
        data = manifest_data()
        data["shared_repositories"][0]["mode"] = "mirror"

        self.assert_validation_error(data)

    def test_read_only_repository_may_omit_sync_owner(self) -> None:
        data = manifest_data()
        data["shared_repositories"][0]["mode"] = "read-only"
        del data["shared_repositories"][0]["sync_owner"]

        self.load_data(data)

    def test_unknown_sync_owner_is_rejected(self) -> None:
        data = manifest_data()
        data["shared_repositories"][0]["sync_owner"] = "nobody"

        self.assert_validation_error(data)

    def test_root_distribution_must_target_data_root(self) -> None:
        data = manifest_data()
        data["root_distribution"]["target"] = "/opt/data/root"

        self.assert_validation_error(data)

    def test_manifest_name_must_be_a_single_relative_filename(self) -> None:
        data = manifest_data()
        data["profiles"][0]["manifest"] = "nested/distribution.yaml"

        self.assert_validation_error(data)

    def test_error_classes_have_stable_exit_codes(self) -> None:
        self.assertEqual(InputError.exit_code, 2)
        self.assertEqual(CredentialError.exit_code, 3)
        self.assertEqual(RepositoryError.exit_code, 4)
        self.assertEqual(MigrationError.exit_code, 5)
        self.assertEqual(ApplyError.exit_code, 6)
        self.assertEqual(RollbackError.exit_code, 7)
        self.assertEqual(ValidationError.exit_code, 8)
        self.assertIsInstance(ValidationError("invalid manifest"), BootstrapError)


if __name__ == "__main__":
    unittest.main()
