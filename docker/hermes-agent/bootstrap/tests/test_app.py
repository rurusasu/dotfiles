from __future__ import annotations

import io
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


BOOTSTRAP_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BOOTSTRAP_ROOT))

from hermes_bootstrap.errors import ApplyError, CredentialError, RollbackError, ValidationError
from hermes_bootstrap.github import GitAuth
from hermes_bootstrap.models import (
    BootstrapManifest,
    DistributionSource,
    SharedRepository,
)
from hermes_bootstrap.payload import SecretRedactor
from hermes_bootstrap.repositories import RemoteSyncResult


def manifest(root: Path) -> BootstrapManifest:
    return BootstrapManifest(
        schema_version=1,
        data_root=root,
        onepassword_items=(),
        root_distribution=DistributionSource(
            "default", "https://github.com/example/root.git", "main", root, "root-distribution.yaml"
        ),
        profiles=(
            DistributionSource(
                "rick",
                "https://github.com/example/rick.git",
                "main",
                root / "profiles" / "rick",
                "distribution.yaml",
            ),
        ),
        shared_repositories=(
            SharedRepository(
                "lifelog",
                "https://github.com/example/lifelog.git",
                "main",
                root / "shared" / "lifelog",
                "read-write",
                "default",
                root / "core" / "lifelog",
            ),
        ),
    )


class FakeTransaction:
    def __init__(self, events: list[str]) -> None:
        self.events = events

    def snapshot(self, path: Path) -> None:
        del path

    def commit(self) -> None:
        self.events.append("commit")

    def rollback(self) -> None:
        self.events.append("rollback")


class AppTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "data"
        self.root.mkdir()
        self.manifest = manifest(self.root)

    def test_apply_recovers_before_reading_secrets_and_network_before_transaction(self) -> None:
        from hermes_bootstrap import app

        events: list[str] = []
        tx = FakeTransaction(events)
        secrets = mock.Mock(github_token="token", redactor=SecretRedactor(("token",)))
        client = mock.Mock(spec=app.GitHubClient)
        staged_root = mock.Mock(declaration=self.manifest.root_distribution)
        staged_profile = mock.Mock(declaration=self.manifest.profiles[0])
        remote = RemoteSyncResult("lifelog", "a" * 40, False, self.root / ".remote")

        def read_payload(stream: io.StringIO, loaded: BootstrapManifest):
            events.append("payload")
            self.assertIs(loaded, self.manifest)
            self.assertEqual(stream.read(), "payload")
            return secrets

        def recover(root: Path) -> None:
            events.append("recover")
            self.assertIs(root, self.root)

        def stage(source: DistributionSource, _scratch: Path, _auth: GitAuth):
            events.append(f"stage:{source.name}")
            return staged_root if source.name == "default" else staged_profile

        def sync(repo: SharedRepository, _auth: GitAuth):
            events.append(f"sync:{repo.name}")
            return remote

        with (
            mock.patch.object(app, "load_manifest", return_value=self.manifest),
            mock.patch.object(app.Transaction, "recover_if_needed", side_effect=recover),
            mock.patch.object(app, "read_secret_payload", side_effect=read_payload),
            mock.patch.object(app, "GitHubClient", return_value=client),
            mock.patch.object(app, "stage_distribution", side_effect=stage),
            mock.patch.object(app, "synchronize_remote", side_effect=sync),
            mock.patch.object(app.Transaction, "begin", return_value=tx),
            mock.patch.object(app, "apply_root_distribution", side_effect=lambda *_: events.append("root")),
            mock.patch.object(app, "apply_profile_distribution", side_effect=lambda *_: events.append("profile:rick")),
            mock.patch.object(app, "apply_shared_working_tree", side_effect=lambda *_: events.append("shared:lifelog")),
            mock.patch.object(app, "build_dashboard_environment", return_value={"DASH": "value"}),
            mock.patch.object(app, "build_profile_environment", side_effect=lambda name, *_: {"PROFILE": name, "GH_TOKEN": "token"}),
            mock.patch.object(app, "merge_env_file", side_effect=lambda path, *_: events.append(f"env:{path.parent.name}")),
            mock.patch.object(app, "validate", side_effect=lambda _: events.append("validate")),
        ):
            result = app.apply(Path("manifest.yaml"), io.StringIO("payload"))

        self.assertEqual(result["status"], "applied")
        self.assertEqual(
            events,
            [
                "recover", "payload", "stage:default", "stage:rick", "sync:lifelog",
                "root", "profile:rick", "shared:lifelog", "env:data", "env:rick", "validate", "commit",
            ],
        )
        self.assertEqual(client.authenticated_login.call_count, 3)
        self.assertEqual(client.assert_repository_access.call_count, 3)

    def test_apply_rolls_back_after_transaction_and_rollback_error_wins(self) -> None:
        from hermes_bootstrap import app

        tx = FakeTransaction([])
        tx.rollback = mock.Mock(side_effect=RollbackError("rollback failed"))  # type: ignore[method-assign]
        with (
            mock.patch.object(app, "load_manifest", return_value=self.manifest),
            mock.patch.object(app.Transaction, "recover_if_needed"),
            mock.patch.object(app, "read_secret_payload", return_value=mock.Mock(github_token="token", redactor=SecretRedactor(("token",)))),
            mock.patch.object(app, "GitHubClient", return_value=mock.Mock(spec=app.GitHubClient)),
            mock.patch.object(app, "_validate_profile_credentials"),
            mock.patch.object(app, "stage_distribution", return_value=mock.Mock()),
            mock.patch.object(app, "synchronize_remote", return_value=RemoteSyncResult("lifelog", "a" * 40, False, self.root / ".remote")),
            mock.patch.object(app.Transaction, "begin", return_value=tx),
            mock.patch.object(app, "apply_root_distribution", side_effect=ApplyError("primary failure")),
        ):
            with self.assertRaisesRegex(RollbackError, "rollback failed"):
                app.apply(Path("manifest.yaml"), io.StringIO("payload"))
        tx.rollback.assert_called_once_with()

    def test_apply_rolls_back_when_a_deterministic_environment_failpoint_fires(self) -> None:
        from hermes_bootstrap import app

        tx = FakeTransaction([])
        secrets = mock.Mock(github_token="token", redactor=SecretRedactor(("token",)))
        remote = RemoteSyncResult("lifelog", "a" * 40, False, self.root / ".remote")

        def failpoint(name: str) -> None:
            if name == "env-merge:rick":
                raise ApplyError("injected failure")

        with (
            mock.patch.object(app, "load_manifest", return_value=self.manifest),
            mock.patch.object(app.Transaction, "recover_if_needed"),
            mock.patch.object(app, "read_secret_payload", return_value=secrets),
            mock.patch.object(app, "GitHubClient", return_value=mock.Mock(spec=app.GitHubClient)),
            mock.patch.object(app, "_validate_profile_credentials"),
            mock.patch.object(app, "stage_distribution", return_value=mock.Mock()),
            mock.patch.object(app, "synchronize_remote", return_value=remote),
            mock.patch.object(app.Transaction, "begin", return_value=tx),
            mock.patch.object(app, "apply_root_distribution"),
            mock.patch.object(app, "apply_profile_distribution"),
            mock.patch.object(app, "apply_shared_working_tree"),
            mock.patch.object(app, "build_dashboard_environment", return_value={"DASH": "value"}),
            mock.patch.object(app, "build_profile_environment", return_value={"GH_TOKEN": "token"}),
            mock.patch.object(app, "merge_env_file"),
            mock.patch.object(app, "_failpoint", side_effect=failpoint),
        ):
            with self.assertRaisesRegex(ApplyError, "injected failure"):
                app.apply(Path("manifest.yaml"), io.StringIO("payload"))
        self.assertEqual(tx.events, ["rollback"])

    def test_validate_is_network_free_and_rejects_an_incomplete_transaction(self) -> None:
        from hermes_bootstrap import app

        with (
            mock.patch.object(app, "load_manifest", return_value=self.manifest),
            mock.patch.object(app.Transaction, "recover_if_needed") as recover,
            mock.patch.object(app, "GitHubClient") as github,
            mock.patch.object(app, "_validate_installed_layout", return_value={"profiles": [], "repositories": []}),
        ):
            result = app.validate(Path("manifest.yaml"))

        self.assertEqual(result, {"status": "valid", "profiles": [], "repositories": []})
        recover.assert_not_called()
        github.assert_not_called()

    def test_sync_repository_uses_process_then_safe_env_files_without_executing_them(self) -> None:
        from hermes_bootstrap import app

        root_env = self.root / ".env"
        root_env.write_text("GH_TOKEN=root-token\n", encoding="utf-8")
        active = self.root.parent / "active"
        active.mkdir()
        (active / ".env").write_text("$(touch should-not-exist)\nGH_TOKEN=active-token\n", encoding="utf-8")
        environ = {"HERMES_HOME": str(active)}
        with (
            mock.patch.object(app, "load_manifest", return_value=self.manifest),
            mock.patch.object(app, "synchronize_named_repository", return_value=RemoteSyncResult("lifelog", "a" * 40, False, self.root / "shared" / "lifelog")) as sync,
        ):
            result = app.sync_repository(Path("manifest.yaml"), "lifelog", environ)

        self.assertEqual(result["name"], "lifelog")
        self.assertFalse((active / "should-not-exist").exists())
        auth = sync.call_args.args[2]
        self.assertEqual(auth.token, "active-token")
        self.assertTrue(sync.call_args.kwargs["require_canonical"])

    def test_sync_repository_rejects_duplicate_or_unsafe_token_files(self) -> None:
        from hermes_bootstrap import app

        (self.root / ".env").write_text("GH_TOKEN=one\nGH_TOKEN=two\n", encoding="utf-8")
        with mock.patch.object(app, "load_manifest", return_value=self.manifest):
            with self.assertRaises(CredentialError):
                app.sync_repository(Path("manifest.yaml"), "lifelog", {})

    def test_validate_fails_closed_for_missing_state_without_leaking_paths(self) -> None:
        from hermes_bootstrap import app

        with mock.patch.object(app, "load_manifest", return_value=self.manifest):
            with self.assertRaises(ValidationError) as raised:
                app.validate(Path("manifest.yaml"))
        self.assertNotIn(str(self.root), str(raised.exception))
