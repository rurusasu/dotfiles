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
import hermes_bootstrap.manifest as manifest_module
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

    def assert_yaml_validation_error(self, content: str | bytes) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "manifest.yaml"
            if isinstance(content, bytes):
                path.write_bytes(content)
            else:
                path.write_text(content, encoding="utf-8")
            with self.assertRaises(ValidationError):
                load_manifest(path)

    def test_approved_manifest_loads_all_targets(self) -> None:
        manifest = load_manifest(APPROVED_MANIFEST)

        self.assertEqual(manifest.schema_version, 1)
        self.assertEqual(manifest.data_root, Path("/opt/data"))
        self.assertEqual(manifest.root_distribution.name, "default")
        self.assertEqual(manifest.root_distribution.target, Path("/opt/data"))
        self.assertEqual(
            tuple(profile.name for profile in manifest.profiles),
            ("rick", "hoffman", "risarisa", "nancy"),
        )
        self.assertEqual(
            tuple(profile.target for profile in manifest.profiles),
            (
                Path("/opt/data/profiles/rick"),
                Path("/opt/data/profiles/hoffman"),
                Path("/opt/data/profiles/risarisa"),
                Path("/opt/data/profiles/nancy"),
            ),
        )
        self.assertEqual(len(manifest.onepassword_items), 7)
        self.assertEqual(
            tuple(item.item for item in manifest.onepassword_items),
            (
                "Hermes Agent Dashboard",
                "GitHubUsedOpenClawPAT",
                "SlackBot-OpenClaw",
                "SlackBot-Rick",
                "SlackBot-Hoffman",
                "SlackBot-Risarisa",
                "SlackBot-Nancy",
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

    def test_profile_targets_must_use_their_profile_namespace(self) -> None:
        for target in (
            "/opt/data/profiles/other",
            "/opt/data/profiles/rick/child",
            "/opt/data/shared/rick",
        ):
            with self.subTest(target=target):
                data = manifest_data()
                data["profiles"][0]["target"] = target

                self.assert_validation_error(data)

    def test_shared_targets_must_use_their_repository_namespace(self) -> None:
        for target in (
            "/opt/data/shared/other",
            "/opt/data/shared/lifelog/child",
            "/opt/data/profiles/lifelog",
        ):
            with self.subTest(target=target):
                data = manifest_data()
                data["shared_repositories"][0]["target"] = target

                self.assert_validation_error(data)

    def test_canonical_targets_cannot_collide_or_overlap(self) -> None:
        for target in (
            "/opt/data/profiles/rick",
            "/opt/data/profiles",
            "/opt/data/profiles/rick/child",
        ):
            with self.subTest(target=target):
                data = manifest_data()
                profile = dict(data["profiles"][0])
                profile["name"] = "morty"
                profile["source"] = "https://github.com/rurusasu/hermes-profile-morty.git"
                profile["target"] = target
                data["profiles"].append(profile)

                self.assert_validation_error(data)

    def test_legacy_target_cannot_equal_or_overlap_a_canonical_target(self) -> None:
        for target in (
            "/opt/data/profiles/rick",
            "/opt/data/profiles",
            "/opt/data/profiles/rick/legacy",
        ):
            with self.subTest(target=target):
                data = manifest_data()
                data["shared_repositories"][0]["legacy_target"] = target

                self.assert_validation_error(data)

    def test_legacy_target_cannot_equal_the_data_root(self) -> None:
        data = manifest_data()
        data["shared_repositories"][0]["legacy_target"] = "/opt/data"

        self.assert_validation_error(data)

    def test_legacy_targets_cannot_overlap_one_another(self) -> None:
        data = manifest_data()
        data["shared_repositories"].append(
            {
                "name": "notes",
                "source": "https://github.com/rurusasu/notes.git",
                "ref": "main",
                "target": "/opt/data/shared/notes",
                "legacy_target": "/opt/data/core/lifelog/archive",
                "mode": "read-only",
            }
        )

        self.assert_validation_error(data)

    def test_managed_path_keeps_an_installed_compatibility_symlink_lexical(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            data_root = Path(directory)
            canonical = data_root / "shared" / "lifelog"
            canonical.mkdir(parents=True)
            legacy = data_root / "core" / "lifelog"
            legacy.parent.mkdir()
            legacy.symlink_to("../shared/lifelog")

            managed = manifest_module._managed_path(
                str(legacy), "manifest.shared_repositories[0].legacy_target", data_root
            )

            self.assertEqual(managed, legacy)

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

    def test_git_refs_follow_check_ref_format_component_rules(self) -> None:
        valid_refs = ("main", "feature/add-thing", "release/v1.0")
        invalid_refs = (
            "@",
            ".hidden",
            "refs/.hidden/main",
            "main.lock",
            "/main",
            "main/",
            "main//next",
            "-main",
            "main.",
            "main..next",
            "main@{next",
            "main next",
            "main~next",
            "main^next",
            "main:next",
            "main?next",
            "main*next",
            "main[next",
            r"main\next",
            "main\x7fnext",
        )

        for ref in valid_refs:
            with self.subTest(ref=ref, valid=True):
                data = manifest_data()
                data["profiles"][0]["ref"] = ref

                self.load_data(data)

        for ref in invalid_refs:
            with self.subTest(ref=ref, valid=False):
                data = manifest_data()
                data["profiles"][0]["ref"] = ref

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

    def test_invalid_utf8_is_reported_as_a_validation_error(self) -> None:
        self.assert_yaml_validation_error(b"schema_version: \xff\n")

    def test_top_level_duplicate_yaml_key_is_rejected(self) -> None:
        content = json.dumps(manifest_data()).replace(
            '"schema_version": 1,',
            '"schema_version": 1, "schema_version": 1,',
            1,
        )

        self.assert_yaml_validation_error(content)

    def test_nested_duplicate_yaml_key_is_rejected(self) -> None:
        content = json.dumps(manifest_data()).replace(
            '"name": "default",',
            '"name": "default", "name": "default",',
            1,
        )

        self.assert_yaml_validation_error(content)

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
