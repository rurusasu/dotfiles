from __future__ import annotations

import io
import json
import os
import socket
import stat
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


BOOTSTRAP_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BOOTSTRAP_ROOT))

import hermes_bootstrap.repositories as repositories_module
from hermes_bootstrap import profile_snapshot
from hermes_bootstrap.errors import (
    ApplyError,
    CredentialError,
    RepositoryError,
    RollbackError,
    ValidationError,
)
from hermes_bootstrap.github import GitAuth
from hermes_bootstrap.models import (
    BootstrapManifest,
    DistributionSource,
    SharedRepository,
)
from hermes_bootstrap.payload import SecretRedactor
from hermes_bootstrap.profile_snapshot import PreparedProfiles
from hermes_bootstrap.profile_sync import (
    ProfileDiff,
    ProfileSyncReport,
    ProfileSyncResult,
)
from hermes_bootstrap.repositories import RemoteSyncResult


def manifest(
    root: Path, profile_names: tuple[str, ...] = ("rick",)
) -> BootstrapManifest:
    return BootstrapManifest(
        schema_version=1,
        data_root=root,
        onepassword_items=(),
        root_distribution=DistributionSource(
            "default", "https://github.com/example/root.git", "main", root, "root-distribution.yaml"
        ),
        profiles=tuple(
            DistributionSource(
                name,
                f"https://github.com/example/{name}.git",
                "main",
                root / "profiles" / name,
                "distribution.yaml",
            )
            for name in profile_names
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


class RecordingEngineLock:
    def __init__(self, events: list[str]) -> None:
        self.events = events

    def require_held(self) -> None:
        self.events.append("lock-require")

    def close(self) -> None:
        self.events.append("lock-close")

    def __enter__(self) -> RecordingEngineLock:
        return self

    def __exit__(self, kind: object, value: object, traceback: object) -> None:
        del kind, value, traceback
        self.close()


class AppTests(unittest.TestCase):
    def setUp(self) -> None:
        from hermes_bootstrap import app

        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(os.path.realpath(self.temp.name)) / "data"
        self.root.mkdir()
        self.manifest = manifest(self.root)
        source_contract_patcher = mock.patch.object(
            app, "validate_chrome_mcp_sources"
        )
        self.validate_chrome_mcp_sources = source_contract_patcher.start()
        self.addCleanup(source_contract_patcher.stop)
        revalidate_patcher = mock.patch.object(
            app,
            "revalidate_profile_snapshots",
            create=True,
        )
        self.revalidate_profile_snapshots = revalidate_patcher.start()
        self.addCleanup(revalidate_patcher.stop)

    def write_installed_profile(
        self,
        *,
        hermes_requires: str = ">=0.18.2",
        owned: list[str] | None = None,
    ) -> Path:
        target = self.root / "profiles" / "rick"
        target.mkdir(parents=True, exist_ok=True)
        (target / "distribution.yaml").write_text(
            json.dumps(
                {
                    "name": "rick",
                    "version": "0.1.0",
                    "hermes_requires": hermes_requires,
                    "distribution_owned": ["config.yaml"] if owned is None else owned,
                    "source": self.manifest.profiles[0].source,
                }
            ),
            encoding="utf-8",
        )
        return target

    def write_root_state(self) -> Path:
        bootstrap = self.root / ".bootstrap"
        bootstrap.mkdir(exist_ok=True)
        state = bootstrap / "root-distribution-state.json"
        state.write_text(
            json.dumps(
                {
                    "source": self.manifest.root_distribution.source,
                    "ref": self.manifest.root_distribution.ref,
                    "commit": "a" * 40,
                    "version": "0.1.0",
                    "distribution_owned": ["config.yaml"],
                }
            ),
            encoding="utf-8",
        )
        (self.root / "config.yaml").write_text("config\n", encoding="utf-8")
        return state

    def write_repository_metadata(self, remote: str) -> None:
        repo = self.manifest.shared_repositories[0]
        git = repo.target / ".git"
        git.mkdir(parents=True)
        (git / "config").write_text(
            f'[core]\n\trepositoryformatversion = 0\n[remote "origin"]\n\turl = {remote}\n',
            encoding="utf-8",
        )
        (git / "HEAD").write_text("a" * 40 + "\n", encoding="ascii")

    def write_valid_layout(self) -> None:
        from hermes_bootstrap import app

        self.write_root_state()
        target = self.write_installed_profile()
        (target / "config.yaml").write_text("config\n", encoding="utf-8")
        self.write_repository_metadata(self.manifest.shared_repositories[0].source)
        secret_body = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

        def environment(keys: frozenset[str]) -> str:
            values = {key: "value" for key in keys}
            values.update({key: "github-token" for key in app.GITHUB_KEYS & keys})
            values["SLACK_BOT_TOKEN"] = "xoxb-valid"
            values["SLACK_APP_TOKEN"] = "xapp-valid"
            values["SLACK_ALLOWED_USERS"] = "UVALID"
            values["HERMES_DASHBOARD_BASIC_AUTH_SECRET"] = secret_body
            if "API_SERVER_KEY" in keys:
                values["API_SERVER_KEY"] = f"hermes-bootstrap-v1_{secret_body}"
            return "".join(f"{key}={values[key]}\n" for key in sorted(keys))

        root_env = environment(app._MANAGED_ENV_KEYS)
        profile_env = environment(app._MANAGED_ENV_KEYS - app.API_SERVER_KEYS)
        for env_path, content in (
            (self.root / ".env", root_env),
            (target / ".env", profile_env),
        ):
            env_path.write_text(content, encoding="utf-8")
            env_path.chmod(0o600)

    def transaction_lock_path(self) -> Path:
        store = self.root / ".bootstrap" / "transactions"
        store.mkdir(parents=True)
        return store / ".lock"

    def test_apply_holds_the_engine_lock_until_staging_cleanup_finishes(self) -> None:
        from hermes_bootstrap import app

        configured = manifest(self.root, ())
        events: list[str] = []
        lock = RecordingEngineLock(events)
        transaction = FakeTransaction(events)
        report = ProfileSyncReport(dry_run=False, profiles=(), exit_code=0)

        def acquire(root: Path) -> RecordingEngineLock:
            self.assertIs(root, self.root)
            events.append("lock-acquire")
            return lock

        def recover(root: Path) -> None:
            self.assertIs(root, self.root)
            events.append("recovery")

        def scratch(root: Path) -> mock.Mock:
            self.assertIs(root, self.root)
            events.append("scratch")
            return mock.Mock(path=self.root / "scratch")

        def begin(root: Path) -> FakeTransaction:
            self.assertIs(root, self.root)
            events.append("transaction-begin")
            return transaction

        with (
            mock.patch.object(app, "load_manifest", return_value=configured),
            mock.patch.object(app.EngineLock, "acquire", side_effect=acquire),
            mock.patch.object(
                app.Transaction, "recover_if_needed", side_effect=recover
            ),
            mock.patch.object(app, "read_secret_payload", return_value=mock.Mock(github_token="token", redactor=SecretRedactor(("token",)))),
            mock.patch.object(app, "_validate_remote_credentials"),
            mock.patch.object(app, "_validate_profile_credentials", return_value={}),
            mock.patch.object(app, "_private_scratch", side_effect=scratch),
            mock.patch.object(
                app, "prepare_profile_snapshots", return_value=PreparedProfiles((), ())
            ),
            mock.patch.object(
                app.profile_sync,
                "synchronize_prepared_profiles",
                return_value=report,
            ),
            mock.patch.object(
                app, "stage_distribution", side_effect=lambda source, *_: mock.Mock(declaration=source)
            ),
            mock.patch.object(
                app,
                "synchronize_remote",
                return_value=RemoteSyncResult("lifelog", "a" * 40, False, self.root / "remote"),
            ),
            mock.patch.object(app.Transaction, "begin", side_effect=begin),
            mock.patch.object(app, "apply_root_distribution"),
            mock.patch.object(app, "apply_shared_working_tree"),
            mock.patch.object(app, "build_dashboard_environment", return_value={}),
            mock.patch.object(app, "build_profile_environment", return_value={}),
            mock.patch.object(app, "merge_env_file"),
            mock.patch.object(app, "_validate_installed_layout", return_value={}),
            mock.patch.object(
                app,
                "_cleanup_apply_resources",
                side_effect=lambda *_: events.append("cleanup") or True,
            ),
        ):
            result = app.apply(Path("manifest.yaml"), io.StringIO("payload"))

        self.assertEqual(result["status"], "applied")
        self.assertLess(events.index("lock-acquire"), events.index("recovery"))
        self.assertLess(events.index("recovery"), events.index("scratch"))
        self.assertLess(events.index("scratch"), events.index("transaction-begin"))
        self.assertLess(events.index("transaction-begin"), events.index("cleanup"))
        self.assertLess(events.index("cleanup"), events.index("lock-close"))

    def test_sync_profiles_holds_the_engine_lock_through_snapshot_cleanup(self) -> None:
        from hermes_bootstrap import app

        events: list[str] = []
        lock = RecordingEngineLock(events)
        report = ProfileSyncReport(dry_run=True, profiles=(), exit_code=0)

        def acquire(root: Path) -> RecordingEngineLock:
            self.assertIs(root, self.root)
            events.append("lock-acquire")
            return lock

        with (
            mock.patch.object(app, "load_manifest", return_value=self.manifest),
            mock.patch.object(app.EngineLock, "acquire", side_effect=acquire),
            mock.patch.object(app, "_runtime_token", return_value="token"),
            mock.patch.object(
                app.profile_sync,
                "create_private_directory",
                side_effect=lambda *_args, **_kwargs: events.append("snapshot-scratch")
                or mock.Mock(path=self.root / "scratch"),
            ),
            mock.patch.object(
                app.profile_sync,
                "prepare_profile_snapshots",
                return_value=PreparedProfiles((), ()),
            ),
            mock.patch.object(
                app.profile_sync,
                "synchronize_prepared_profiles",
                side_effect=lambda *_args, **_kwargs: events.append("publication")
                or report,
            ),
            mock.patch.object(
                app.profile_sync,
                "_cleanup_resources",
                side_effect=lambda *_args, **_kwargs: events.append("cleanup")
                or False,
            ),
        ):
            result = app.sync_profiles(Path("manifest.yaml"), dry_run=True, environ={})

        self.assertIs(result, report)
        self.assertLess(events.index("lock-acquire"), events.index("snapshot-scratch"))
        self.assertLess(events.index("snapshot-scratch"), events.index("publication"))
        self.assertLess(events.index("publication"), events.index("cleanup"))
        self.assertLess(events.index("cleanup"), events.index("lock-close"))

    def test_sync_repository_holds_the_engine_lock_through_real_askpass_cleanup(
        self,
    ) -> None:
        from hermes_bootstrap import app

        events: list[str] = []
        lock = RecordingEngineLock(events)
        repository = self.manifest.shared_repositories[0]
        (repository.target / ".git").mkdir(parents=True)

        def acquire(root: Path) -> RecordingEngineLock:
            self.assertIs(root, self.root)
            events.append("lock-acquire")
            return lock

        def synchronize(*_args: object, **_kwargs: object) -> tuple[str, bool]:
            events.append("repository-sync")
            return "a" * 40, False

        real_unlink = repositories_module._unlink_path

        def cleanup(path: Path) -> bool:
            self.assertTrue(path.name.startswith("askpass-"))
            self.assertTrue(path.exists())
            events.append("repository-cleanup")
            return real_unlink(path)

        with (
            mock.patch.object(app, "load_manifest", return_value=self.manifest),
            mock.patch.object(app.EngineLock, "acquire", side_effect=acquire),
            mock.patch.object(app, "_runtime_token", return_value="token"),
            mock.patch.object(
                repositories_module, "_verify_checkout_identity"
            ),
            mock.patch.object(
                repositories_module, "_synchronize_checkout", side_effect=synchronize
            ),
            mock.patch.object(
                repositories_module, "_unlink_path", side_effect=cleanup
            ),
        ):
            result = app.sync_repository(Path("manifest.yaml"), "lifelog", {})

        self.assertEqual(result["name"], "lifelog")
        self.assertLess(events.index("lock-acquire"), events.index("repository-sync"))
        self.assertLess(events.index("repository-sync"), events.index("repository-cleanup"))
        self.assertLess(events.index("repository-cleanup"), events.index("lock-close"))

    def test_secret_plan_and_validate_do_not_acquire_the_engine_lock(self) -> None:
        from hermes_bootstrap import app

        with (
            mock.patch.object(app, "load_manifest", return_value=self.manifest),
            mock.patch.object(app, "build_secret_plan", return_value={}),
            mock.patch.object(
                app,
                "_validate_installed_layout",
                return_value={"profiles": [], "repositories": []},
            ),
            mock.patch.object(app.EngineLock, "acquire") as acquire,
        ):
            self.assertEqual(app.secret_plan(Path("manifest.yaml")), {})
            self.assertEqual(
                app.validate(Path("manifest.yaml")),
                {"status": "valid", "profiles": [], "repositories": []},
            )

        acquire.assert_not_called()

    def test_engine_lock_contention_blocks_mutating_work_before_side_effects(self) -> None:
        from hermes_bootstrap import app

        events: list[str] = []

        def unavailable(_root: Path) -> RecordingEngineLock:
            events.append("lock-acquire")
            raise RepositoryError("bootstrap engine lock is unavailable")

        with (
            mock.patch.object(app, "load_manifest", return_value=self.manifest),
            mock.patch.object(app.EngineLock, "acquire", side_effect=unavailable),
            mock.patch.object(app.Transaction, "recover_if_needed", side_effect=lambda *_: events.append("recovery")),
            mock.patch.object(app, "_private_scratch", side_effect=lambda *_: events.append("scratch")),
            mock.patch.object(app, "stage_distribution", side_effect=lambda *_: events.append("git")),
            mock.patch.object(app, "synchronize_remote", side_effect=lambda *_: events.append("git")),
            mock.patch.object(app.Transaction, "begin", side_effect=lambda *_: events.append("transaction")),
        ):
            with self.assertRaisesRegex(RepositoryError, "bootstrap engine lock is unavailable"):
                app.apply(Path("manifest.yaml"), io.StringIO("payload"))

        self.assertEqual(events, ["lock-acquire"])

        events.clear()
        with (
            mock.patch.object(app, "load_manifest", return_value=self.manifest),
            mock.patch.object(app.EngineLock, "acquire", side_effect=unavailable),
            mock.patch.object(app, "_runtime_token", side_effect=lambda *_: events.append("token")),
            mock.patch.object(
                app.profile_sync,
                "synchronize_profiles",
                side_effect=lambda *_args, **_kwargs: events.append("git"),
            ),
        ):
            report = app.sync_profiles(Path("manifest.yaml"), dry_run=False, environ={})

        self.assertEqual(events, ["lock-acquire"])
        self.assertEqual(report.exit_code, RepositoryError.exit_code)
        self.assertTrue(
            all(profile.category == "repository" for profile in report.profiles)
        )

        events.clear()
        with (
            mock.patch.object(app, "load_manifest", return_value=self.manifest),
            mock.patch.object(app.EngineLock, "acquire", side_effect=unavailable),
            mock.patch.object(app, "_runtime_token", side_effect=lambda *_: events.append("token")),
            mock.patch.object(
                app,
                "synchronize_named_repository",
                side_effect=lambda *_args, **_kwargs: events.append("git"),
            ),
        ):
            with self.assertRaisesRegex(
                RepositoryError, "bootstrap engine lock is unavailable"
            ):
                app.sync_repository(Path("manifest.yaml"), "lifelog", {})

        self.assertEqual(events, ["lock-acquire"])

    def test_apply_recovers_before_reading_secrets_and_network_before_transaction(self) -> None:
        from hermes_bootstrap import app

        configured = manifest(
            self.root, ("rick", "hoffman", "risarisa", "nancy")
        )
        events: list[str] = []
        tx = FakeTransaction(events)
        secrets = mock.Mock(github_token="token", redactor=SecretRedactor(("token",)))
        client = mock.Mock(spec=app.GitHubClient)
        snapshots = tuple(
            mock.Mock(declaration=profile) for profile in configured.profiles
        )
        prepared = PreparedProfiles(snapshots, ())
        commits = {
            profile.name: str(index) * 40
            for index, profile in enumerate(configured.profiles, start=1)
        }
        statuses = {
            "rick": "changed",
            "hoffman": "unchanged",
            "risarisa": "changed",
            "nancy": "unchanged",
        }
        profile_report = ProfileSyncReport(
            dry_run=False,
            profiles=tuple(
                ProfileSyncResult(
                    name=profile.name,
                    status=statuses[profile.name],  # type: ignore[arg-type]
                    commit=commits[profile.name],
                    snapshot=f"snapshot-{profile.name}",
                    diff=ProfileDiff(),
                    category=statuses[profile.name],
                    message="safe",
                )
                for profile in configured.profiles
            ),
            exit_code=0,
        )
        remote = RemoteSyncResult("lifelog", "a" * 40, False, self.root / ".remote")
        staged_sources: list[DistributionSource] = []

        def read_payload(stream: io.StringIO, loaded: BootstrapManifest):
            events.append("payload")
            self.assertIs(loaded, configured)
            self.assertEqual(stream.read(), "payload")
            return secrets

        def recover(root: Path) -> None:
            events.append("recover")
            self.assertIs(root, self.root)

        def prepare(
            loaded: BootstrapManifest, _scratch: Path, *, allow_missing: bool
        ) -> PreparedProfiles:
            events.append("profile-preflight")
            self.assertIs(loaded, configured)
            self.assertTrue(allow_missing)
            return prepared

        def sync_profiles(
            sync_prepared: PreparedProfiles, _auth: GitAuth, *, dry_run: bool
        ) -> ProfileSyncReport:
            self.assertEqual(sync_prepared.missing, ())
            self.assertEqual(sync_prepared.snapshots, snapshots)
            self.assertFalse(dry_run)
            events.extend(
                f"profile-sync:{snapshot.declaration.name}"
                for snapshot in sync_prepared.snapshots
            )
            return profile_report

        def stage(source: DistributionSource, _scratch: Path, _auth: GitAuth):
            staged_sources.append(source)
            if source.name == "default":
                events.append("stage:default")
            else:
                events.append(f"stage:{source.name}:{source.ref}")
            return mock.Mock(declaration=source)

        def sync(repo: SharedRepository, _auth: GitAuth):
            events.append(f"sync:{repo.name}")
            return remote

        def begin(root: Path) -> FakeTransaction:
            self.assertIs(root, self.root)
            self.assertEqual(
                events,
                [
                    "recover",
                    "payload",
                    "profile-preflight",
                    "profile-sync:rick",
                    "profile-sync:hoffman",
                    "profile-sync:risarisa",
                    "profile-sync:nancy",
                    "stage:default",
                    f"stage:rick:{commits['rick']}",
                    f"stage:hoffman:{commits['hoffman']}",
                    f"stage:risarisa:{commits['risarisa']}",
                    f"stage:nancy:{commits['nancy']}",
                    "source-contract:default,rick,hoffman,risarisa,nancy",
                    "sync:lifelog",
                    "revalidate",
                ],
            )
            return tx

        def validate_installed(
            loaded: BootstrapManifest, *, allow_active_transaction: bool
        ) -> dict[str, list[str]]:
            self.assertIs(loaded, configured)
            self.assertTrue(allow_active_transaction)
            events.append("validate")
            return {
                "profiles": [profile.name for profile in configured.profiles],
                "repositories": ["lifelog"],
            }

        self.validate_chrome_mcp_sources.side_effect = (
            lambda staged: events.append(
                "source-contract:"
                + ",".join(stage.declaration.name for stage in staged)
            )
        )
        self.revalidate_profile_snapshots.side_effect = (
            lambda _manifest, _baseline, _scratch: events.append("revalidate")
        )

        with (
            mock.patch.object(app, "load_manifest", return_value=configured),
            mock.patch.object(app.Transaction, "recover_if_needed", side_effect=recover),
            mock.patch.object(app, "read_secret_payload", side_effect=read_payload),
            mock.patch.object(app, "GitHubClient", return_value=client),
            mock.patch.object(app, "prepare_profile_snapshots", side_effect=prepare),
            mock.patch.object(
                app.profile_sync,
                "synchronize_prepared_profiles",
                side_effect=sync_profiles,
            ),
            mock.patch.object(app, "stage_distribution", side_effect=stage),
            mock.patch.object(app, "synchronize_remote", side_effect=sync),
            mock.patch.object(app.Transaction, "begin", side_effect=begin),
            mock.patch.object(app, "apply_root_distribution", side_effect=lambda *_: events.append("root")),
            mock.patch.object(
                app,
                "apply_profile_distribution",
                side_effect=lambda stage, *_args, **_kwargs: events.append(
                    f"profile:{stage.declaration.name}"
                ),
            ),
            mock.patch.object(app, "apply_shared_working_tree", side_effect=lambda *_: events.append("shared:lifelog")),
            mock.patch.object(app, "build_dashboard_environment", return_value={"DASH": "value"}),
            mock.patch.object(app, "build_profile_environment", side_effect=lambda name, *_: {"PROFILE": name, "GH_TOKEN": "token"}),
            mock.patch.object(app, "merge_env_file", side_effect=lambda path, *_: events.append(f"env:{path.parent.name}")),
            mock.patch.object(app, "_validate_installed_layout", side_effect=validate_installed),
        ):
            result = app.apply(Path("manifest.yaml"), io.StringIO("payload"))

        self.assertEqual(result["status"], "applied")
        self.assertEqual(result["profile_sync"], statuses)
        self.assertEqual(
            events,
            [
                "recover",
                "payload",
                "profile-preflight",
                "profile-sync:rick",
                "profile-sync:hoffman",
                "profile-sync:risarisa",
                "profile-sync:nancy",
                "stage:default",
                f"stage:rick:{commits['rick']}",
                f"stage:hoffman:{commits['hoffman']}",
                f"stage:risarisa:{commits['risarisa']}",
                f"stage:nancy:{commits['nancy']}",
                "source-contract:default,rick,hoffman,risarisa,nancy",
                "sync:lifelog",
                "revalidate",
                "root",
                "profile:rick",
                "profile:hoffman",
                "profile:risarisa",
                "profile:nancy",
                "shared:lifelog",
                "env:data",
                "env:rick",
                "env:hoffman",
                "env:risarisa",
                "env:nancy",
                "validate",
                "commit",
            ],
        )
        self.assertEqual(
            [source.name for source in staged_sources],
            ["default", "rick", "hoffman", "risarisa", "nancy"],
        )
        for source, declaration in zip(staged_sources[1:], configured.profiles):
            self.assertEqual(source.source, declaration.source)
            self.assertEqual(source.ref, commits[source.name])
        self.assertEqual(client.authenticated_login.call_count, 6)
        self.assertEqual(client.assert_repository_access.call_count, 6)

    def test_apply_installs_only_missing_profiles_from_their_configured_remote_branch(
        self,
    ) -> None:
        from hermes_bootstrap import app

        configured = manifest(self.root, ("rick", "nancy"))
        existing = mock.Mock(declaration=configured.profiles[0])
        prepared = PreparedProfiles((existing,), (configured.profiles[1],))
        exact_commit = "1" * 40
        report = ProfileSyncReport(
            dry_run=False,
            profiles=(
                ProfileSyncResult(
                    "rick",
                    "unchanged",
                    exact_commit,
                    "snapshot-rick",
                    ProfileDiff(),
                    "unchanged",
                    "safe",
                ),
            ),
            exit_code=0,
        )
        tx = FakeTransaction([])
        staged_sources: list[DistributionSource] = []
        applied_profiles: list[tuple[str, dict[str, object]]] = []

        def stage(source: DistributionSource, _scratch: Path, _auth: GitAuth):
            staged_sources.append(source)
            return mock.Mock(declaration=source)

        with (
            mock.patch.object(app, "load_manifest", return_value=configured),
            mock.patch.object(app.Transaction, "recover_if_needed"),
            mock.patch.object(
                app,
                "read_secret_payload",
                return_value=mock.Mock(
                    github_token="token", redactor=SecretRedactor(("token",))
                ),
            ),
            mock.patch.object(app, "_validate_remote_credentials"),
            mock.patch.object(app, "_validate_profile_credentials"),
            mock.patch.object(
                app, "prepare_profile_snapshots", return_value=prepared
            ),
            mock.patch.object(
                app.profile_sync,
                "synchronize_prepared_profiles",
                return_value=report,
            ) as sync,
            mock.patch.object(app, "stage_distribution", side_effect=stage),
            mock.patch.object(
                app,
                "synchronize_remote",
                return_value=RemoteSyncResult(
                    "lifelog", "a" * 40, False, self.root / "shared" / "lifelog"
                ),
            ),
            mock.patch.object(app.Transaction, "begin", return_value=tx),
            mock.patch.object(app, "apply_root_distribution"),
            mock.patch.object(
                app,
                "apply_profile_distribution",
                side_effect=lambda staged, *_args, **kwargs: (
                    self.assertFalse(kwargs["replace_existing"]),
                    applied_profiles.append(
                        (staged.declaration.name, kwargs)
                    ),
                )[-1],
            ),
            mock.patch.object(app, "apply_shared_working_tree"),
            mock.patch.object(
                app, "build_dashboard_environment", return_value={"DASH": "value"}
            ),
            mock.patch.object(
                app,
                "build_profile_environment",
                return_value={"GH_TOKEN": "token"},
            ),
            mock.patch.object(app, "merge_env_file") as merge_env,
            mock.patch.object(app, "_validate_installed_layout"),
        ):
            result = app.apply(Path("manifest.yaml"), io.StringIO("payload"))

        sync_prepared = sync.call_args.args[0]
        self.assertEqual(sync_prepared.snapshots, (existing,))
        self.assertEqual(sync_prepared.missing, ())
        self.assertEqual(
            [(source.name, source.ref) for source in staged_sources],
            [
                ("default", "main"),
                ("rick", exact_commit),
                ("nancy", "main"),
            ],
        )
        self.assertEqual(
            [name for name, _kwargs in applied_profiles],
            ["rick", "nancy"],
        )
        self.assertNotIn("managed_environment", applied_profiles[0][1])
        self.assertIs(applied_profiles[0][1]["expected_missing"], False)
        self.assertEqual(
            applied_profiles[1][1]["managed_environment"],
            {"GH_TOKEN": "token"},
        )
        self.assertIs(applied_profiles[1][1]["expected_missing"], True)
        self.assertEqual(
            [call.args[0] for call in merge_env.call_args_list],
            [
                configured.data_root / ".env",
                configured.profiles[0].target / ".env",
            ],
        )
        self.assertEqual(
            result["profile_sync"],
            {"rick": "unchanged", "nancy": "installed"},
        )

    def test_apply_rejects_existing_and_new_profile_drift_at_every_late_checkpoint(
        self,
    ) -> None:
        from hermes_bootstrap import app

        checkpoints = (
            "profile-publication",
            "distribution-staging",
            "chrome-validation",
            "shared-remote-sync",
        )
        for checkpoint in checkpoints:
            for mutation in ("existing-edit", "missing-target-creation"):
                with self.subTest(checkpoint=checkpoint, mutation=mutation):
                    case_root = self.root.parent / f"{checkpoint}-{mutation}"
                    case_root.mkdir()
                    configured = manifest(case_root)
                    target = configured.profiles[0].target
                    if mutation == "existing-edit":
                        target.mkdir(parents=True)
                        (target / "distribution.yaml").write_text(
                            json.dumps(
                                {
                                    "name": "rick",
                                    "version": "0.1.0",
                                    "hermes_requires": ">=0.18.2",
                                    "distribution_owned": ["config.yaml"],
                                    "source": configured.profiles[0].source,
                                }
                            ),
                            encoding="ascii",
                        )
                        (target / "config.yaml").write_bytes(b"original\n")
                        (target / "config.yaml").chmod(0o644)

                    report = ProfileSyncReport(
                        dry_run=False,
                        profiles=(
                            (
                                ProfileSyncResult(
                                    "rick",
                                    "changed",
                                    "1" * 40,
                                    "snapshot-rick",
                                    ProfileDiff(),
                                    "published",
                                    "safe",
                                ),
                            )
                            if mutation == "existing-edit"
                            else ()
                        ),
                        exit_code=0,
                    )
                    expected_after: dict[
                        str, tuple[str, int, bytes | None]
                    ] | None = None
                    mutated = False

                    def snapshot_target() -> dict[
                        str, tuple[str, int, bytes | None]
                    ]:
                        return {
                            path.relative_to(target).as_posix(): (
                                "directory" if path.is_dir() else "file",
                                stat.S_IMODE(path.stat().st_mode),
                                None if path.is_dir() else path.read_bytes(),
                            )
                            for path in (target, *sorted(target.rglob("*")))
                        }

                    def mutate() -> None:
                        nonlocal expected_after, mutated
                        if mutated:
                            return
                        mutated = True
                        if mutation == "existing-edit":
                            config = target / "config.yaml"
                            config.write_bytes(b"late-edit\n")
                            config.chmod(0o600)
                        else:
                            target.mkdir(parents=True)
                            (target / "distribution.yaml").write_text(
                                json.dumps(
                                    {
                                        "name": "rick",
                                        "version": "9.9.9",
                                        "hermes_requires": ">=0.18.2",
                                        "distribution_owned": ["config.yaml"],
                                    }
                                ),
                                encoding="ascii",
                            )
                            (target / "config.yaml").write_bytes(
                                b"new-local-profile\n"
                            )
                            (target / "config.yaml").chmod(0o600)
                        expected_after = snapshot_target()

                    def synchronize_profiles(
                        *_args: object,
                        **_kwargs: object,
                    ) -> ProfileSyncReport:
                        if checkpoint == "profile-publication":
                            mutate()
                        return report

                    def stage(
                        source: DistributionSource,
                        *_args: object,
                    ) -> mock.Mock:
                        if (
                            checkpoint == "distribution-staging"
                            and source.name == "rick"
                        ):
                            mutate()
                        return mock.Mock(declaration=source)

                    def validate_stages(_stages: object) -> None:
                        if checkpoint == "chrome-validation":
                            mutate()

                    def synchronize_shared(
                        *_args: object,
                    ) -> RemoteSyncResult:
                        if checkpoint == "shared-remote-sync":
                            mutate()
                        return RemoteSyncResult(
                            "lifelog",
                            "a" * 40,
                            False,
                            case_root / "shared" / "lifelog",
                        )

                    self.revalidate_profile_snapshots.side_effect = (
                        profile_snapshot.revalidate_profile_snapshots
                    )
                    self.validate_chrome_mcp_sources.side_effect = validate_stages
                    with (
                        mock.patch.object(
                            app,
                            "load_manifest",
                            return_value=configured,
                        ),
                        mock.patch.object(
                            app.Transaction,
                            "recover_if_needed",
                        ),
                        mock.patch.object(
                            app,
                            "read_secret_payload",
                            return_value=mock.Mock(
                                github_token="token",
                                redactor=SecretRedactor(("token",)),
                            ),
                        ),
                        mock.patch.object(
                            app,
                            "_validate_remote_credentials",
                        ),
                        mock.patch.object(
                            app,
                            "_validate_profile_credentials",
                            return_value={},
                        ),
                        mock.patch.object(
                            app.profile_sync,
                            "synchronize_prepared_profiles",
                            side_effect=synchronize_profiles,
                        ),
                        mock.patch.object(
                            app,
                            "stage_distribution",
                            side_effect=stage,
                        ),
                        mock.patch.object(
                            app,
                            "synchronize_remote",
                            side_effect=synchronize_shared,
                        ),
                        mock.patch.object(
                            app.Transaction,
                            "begin",
                        ) as transaction_begin,
                        mock.patch.object(
                            app,
                            "apply_root_distribution",
                        ),
                        mock.patch.object(
                            app,
                            "apply_profile_distribution",
                        ) as apply_profile,
                        mock.patch.object(
                            app,
                            "apply_shared_working_tree",
                        ),
                        mock.patch.object(
                            app,
                            "build_profile_environment",
                            return_value={},
                        ),
                        mock.patch.object(app, "merge_env_file"),
                        mock.patch.object(app, "_validate_installed_layout"),
                        mock.patch.object(
                            app,
                            "_cleanup_apply_resources",
                            return_value=True,
                        ),
                        self.assertRaises(RepositoryError) as raised,
                    ):
                        app.apply(
                            Path("manifest.yaml"),
                            io.StringIO("payload"),
                        )

                    self.assertTrue(mutated)
                    transaction_begin.assert_not_called()
                    apply_profile.assert_not_called()
                    self.assertEqual(snapshot_target(), expected_after)
                    self.assertEqual(
                        str(raised.exception),
                        "profile snapshot rejected (local_profile_changed)",
                    )
                    failure = raised.exception.profile_sync_report.profiles[0]
                    self.assertEqual(failure.name, "rick")
                    self.assertEqual(
                        failure.category,
                        "local_profile_changed",
                    )

    def test_apply_rejects_an_invalid_existing_profile_without_remote_fallback(
        self,
    ) -> None:
        from hermes_bootstrap import app

        target = self.root / "profiles" / "rick"
        target.mkdir(parents=True)
        invalid = b"name: rick\nversion: [\n"
        (target / "distribution.yaml").write_bytes(invalid)

        with (
            mock.patch.object(app, "load_manifest", return_value=self.manifest),
            mock.patch.object(app.Transaction, "recover_if_needed"),
            mock.patch.object(
                app,
                "read_secret_payload",
                return_value=mock.Mock(
                    github_token="token", redactor=SecretRedactor(("token",))
                ),
            ),
            mock.patch.object(app, "_validate_remote_credentials"),
            mock.patch.object(app, "_validate_profile_credentials"),
            mock.patch.object(
                app.profile_sync, "synchronize_prepared_profiles"
            ) as sync,
            mock.patch.object(app, "stage_distribution") as stage,
            mock.patch.object(app, "synchronize_remote") as shared_sync,
            mock.patch.object(app.Transaction, "begin") as begin,
            self.assertRaises(RepositoryError),
        ):
            app.apply(Path("manifest.yaml"), io.StringIO("payload"))

        sync.assert_not_called()
        stage.assert_not_called()
        shared_sync.assert_not_called()
        begin.assert_not_called()
        self.assertEqual((target / "distribution.yaml").read_bytes(), invalid)
        self.assertFalse(any(self.root.glob(".hermes-bootstrap-*")))

    def test_profile_sync_failure_precedes_mutation_and_preserves_partial_report(
        self,
    ) -> None:
        from hermes_bootstrap import app

        configured = manifest(
            self.root, ("rick", "hoffman", "risarisa", "nancy")
        )
        prepared = PreparedProfiles(
            tuple(mock.Mock(declaration=profile) for profile in configured.profiles),
            (),
        )
        report = ProfileSyncReport(
            dry_run=False,
            profiles=(
                ProfileSyncResult(
                    "rick",
                    "changed",
                    "1" * 40,
                    "snapshot-rick",
                    ProfileDiff(),
                    "published",
                    "safe",
                ),
                ProfileSyncResult(
                    "hoffman",
                    "failed",
                    None,
                    "snapshot-hoffman",
                    ProfileDiff(),
                    "repository",
                    "safe",
                ),
                ProfileSyncResult(
                    "risarisa",
                    "changed",
                    "3" * 40,
                    "snapshot-risarisa",
                    ProfileDiff(),
                    "published",
                    "safe",
                ),
                ProfileSyncResult(
                    "nancy",
                    "failed",
                    None,
                    "snapshot-nancy",
                    ProfileDiff(),
                    "repository",
                    "safe",
                ),
            ),
            exit_code=RepositoryError.exit_code,
        )

        with (
            mock.patch.object(app, "load_manifest", return_value=configured),
            mock.patch.object(app.Transaction, "recover_if_needed"),
            mock.patch.object(
                app,
                "read_secret_payload",
                return_value=mock.Mock(
                    github_token="token", redactor=SecretRedactor(("token",))
                ),
            ),
            mock.patch.object(app, "_validate_remote_credentials"),
            mock.patch.object(app, "_validate_profile_credentials"),
            mock.patch.object(
                app, "prepare_profile_snapshots", return_value=prepared
            ),
            mock.patch.object(
                app.profile_sync,
                "synchronize_prepared_profiles",
                return_value=report,
            ),
            mock.patch.object(app, "stage_distribution") as stage,
            mock.patch.object(app, "synchronize_remote") as shared_sync,
            mock.patch.object(app.Transaction, "begin") as begin,
            mock.patch.object(app, "apply_root_distribution") as apply_root,
            mock.patch.object(app, "apply_profile_distribution") as apply_profile,
            mock.patch.object(app, "apply_shared_working_tree") as apply_shared,
            self.assertRaisesRegex(
                RepositoryError,
                r"^named profile repository sync failed: hoffman,nancy$",
            ) as caught,
        ):
            app.apply(Path("manifest.yaml"), io.StringIO("payload"))

        stage.assert_not_called()
        shared_sync.assert_not_called()
        begin.assert_not_called()
        apply_root.assert_not_called()
        apply_profile.assert_not_called()
        apply_shared.assert_not_called()
        self.assertIs(caught.exception.profile_sync_report, report)
        self.assertEqual(
            [
                (item.name, item.status, item.commit)
                for item in caught.exception.profile_sync_report.profiles
            ],
            [
                ("rick", "changed", "1" * 40),
                ("hoffman", "failed", None),
                ("risarisa", "changed", "3" * 40),
                ("nancy", "failed", None),
            ],
        )
        self.assertNotIn("rick", str(caught.exception))
        self.assertNotIn("risarisa", str(caught.exception))
        self.assertFalse(any(self.root.glob(".hermes-bootstrap-*")))

    def test_apply_cleans_profile_snapshots_and_git_stages_without_local_changes(
        self,
    ) -> None:
        from hermes_bootstrap import app

        target = self.write_installed_profile()
        config = target / "config.yaml"
        config.write_bytes(b"local-authoritative\n")
        config.chmod(0o640)
        manifest_path = target / "distribution.yaml"
        before = {
            path.name: (path.read_bytes(), stat.S_IMODE(path.stat().st_mode))
            for path in (manifest_path, config)
        }
        exact_commit = "1" * 40
        report = ProfileSyncReport(
            dry_run=False,
            profiles=(
                ProfileSyncResult(
                    "rick",
                    "unchanged",
                    exact_commit,
                    "snapshot-rick",
                    ProfileDiff(),
                    "unchanged",
                    "safe",
                ),
            ),
            exit_code=0,
        )
        tx = FakeTransaction([])

        def sync_profiles(
            prepared: PreparedProfiles, _auth: GitAuth, *, dry_run: bool
        ) -> ProfileSyncReport:
            self.assertFalse(dry_run)
            git_scratch = prepared.snapshots[0].root.parent / "git-scratch"
            git_scratch.mkdir()
            (git_scratch / "private").write_bytes(b"temporary")
            return report

        def stage(source: DistributionSource, scratch: Path, _auth: GitAuth):
            stage_root = scratch / f"stage-{source.name}"
            stage_root.mkdir()
            (stage_root / "private").write_bytes(b"temporary")
            return mock.Mock(declaration=source)

        with (
            mock.patch.object(app, "load_manifest", return_value=self.manifest),
            mock.patch.object(app.Transaction, "recover_if_needed"),
            mock.patch.object(
                app,
                "read_secret_payload",
                return_value=mock.Mock(
                    github_token="token", redactor=SecretRedactor(("token",))
                ),
            ),
            mock.patch.object(app, "_validate_remote_credentials"),
            mock.patch.object(app, "_validate_profile_credentials"),
            mock.patch.object(
                app.profile_sync,
                "synchronize_prepared_profiles",
                side_effect=sync_profiles,
            ),
            mock.patch.object(app, "stage_distribution", side_effect=stage),
            mock.patch.object(
                app,
                "synchronize_remote",
                return_value=RemoteSyncResult(
                    "lifelog", "a" * 40, False, self.root / "shared" / "lifelog"
                ),
            ),
            mock.patch.object(app.Transaction, "begin", return_value=tx),
            mock.patch.object(app, "apply_root_distribution"),
            mock.patch.object(app, "apply_profile_distribution"),
            mock.patch.object(app, "apply_shared_working_tree"),
            mock.patch.object(
                app, "build_dashboard_environment", return_value={"DASH": "value"}
            ),
            mock.patch.object(
                app,
                "build_profile_environment",
                return_value={"GH_TOKEN": "token"},
            ),
            mock.patch.object(app, "merge_env_file"),
            mock.patch.object(app, "_validate_installed_layout"),
        ):
            result = app.apply(Path("manifest.yaml"), io.StringIO("payload"))

        self.assertEqual(result["profile_sync"], {"rick": "unchanged"})
        self.assertEqual(
            {
                path.name: (path.read_bytes(), stat.S_IMODE(path.stat().st_mode))
                for path in (manifest_path, config)
            },
            before,
        )
        self.assertFalse(any(self.root.glob(".hermes-bootstrap-*")))

    def test_source_contract_failure_precedes_remote_sync_and_transaction(self) -> None:
        from hermes_bootstrap import app

        secrets = mock.Mock(
            github_token="token",
            redactor=SecretRedactor(("token",)),
        )
        staged = mock.Mock()
        self.validate_chrome_mcp_sources.side_effect = ValidationError(
            "distribution 'future-profile' config.yaml has invalid Chrome MCP configuration"
        )

        with (
            mock.patch.object(app, "load_manifest", return_value=self.manifest),
            mock.patch.object(app.Transaction, "recover_if_needed"),
            mock.patch.object(app, "read_secret_payload", return_value=secrets),
            mock.patch.object(app, "_validate_remote_credentials"),
            mock.patch.object(app, "_validate_profile_credentials"),
            mock.patch.object(app, "stage_distribution", return_value=staged),
            mock.patch.object(app, "synchronize_remote") as synchronize,
            mock.patch.object(app.Transaction, "begin") as begin,
        ):
            with self.assertRaisesRegex(
                ValidationError, "future-profile.*config.yaml"
            ):
                app.apply(Path("manifest.yaml"), io.StringIO("payload"))

        self.assertEqual(
            self.validate_chrome_mcp_sources.call_args.args[0],
            [staged, staged],
        )
        synchronize.assert_not_called()
        begin.assert_not_called()

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

    def test_apply_public_traceback_contains_no_sensitive_orchestration_frames(self) -> None:
        from hermes_bootstrap import app

        token = "traceback-token-marker"
        secrets = mock.Mock(github_token=token, redactor=SecretRedactor((token,)))
        with (
            mock.patch.object(app, "load_manifest", return_value=self.manifest),
            mock.patch.object(app.Transaction, "recover_if_needed"),
            mock.patch.object(app, "read_secret_payload", return_value=secrets),
            mock.patch.object(app, "_validate_remote_credentials", side_effect=RuntimeError(token)),
        ):
            try:
                app.apply(Path("manifest.yaml"), io.StringIO(token))
            except ApplyError as error:
                raised = error
            else:
                self.fail("ApplyError was not raised")

        traceback = raised.__traceback__
        frame_names: set[str] = set()
        while traceback is not None:
            if traceback.tb_frame.f_code.co_filename.endswith("hermes_bootstrap/app.py"):
                frame_names.update(traceback.tb_frame.f_locals)
                for value in traceback.tb_frame.f_locals.values():
                    self.assertNotIn(token, repr(value))
            traceback = traceback.tb_next
        self.assertTrue(
            frame_names.isdisjoint({"secrets", "auth", "dashboard", "environment", "token"})
        )
        self.assertIsNone(raised.__context__)

    def test_apply_rolls_back_when_a_deterministic_environment_failpoint_fires(self) -> None:
        from hermes_bootstrap import app

        tx = FakeTransaction([])
        secrets = mock.Mock(github_token="token", redactor=SecretRedactor(("token",)))
        remote = RemoteSyncResult("lifelog", "a" * 40, False, self.root / ".remote")

        def failpoint(name: str) -> None:
            if name == "env-merge:default":
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

    def test_apply_rolls_back_when_internal_validation_fails_before_commit(self) -> None:
        from hermes_bootstrap import app

        events: list[str] = []
        tx = FakeTransaction(events)
        secrets = mock.Mock(github_token="token", redactor=SecretRedactor(("token",)))
        remote = RemoteSyncResult("lifelog", "a" * 40, False, self.root / ".remote")

        def validate_installed(
            loaded: BootstrapManifest, *, allow_active_transaction: bool
        ) -> dict[str, list[str]]:
            self.assertIs(loaded, self.manifest)
            self.assertTrue(allow_active_transaction)
            events.append("validate")
            raise ValidationError("installed layout failed")

        with (
            mock.patch.object(app, "load_manifest", return_value=self.manifest),
            mock.patch.object(app.Transaction, "recover_if_needed"),
            mock.patch.object(app, "read_secret_payload", return_value=secrets),
            mock.patch.object(app, "_validate_remote_credentials"),
            mock.patch.object(app, "_validate_profile_credentials"),
            mock.patch.object(app, "stage_distribution", return_value=mock.Mock()),
            mock.patch.object(app, "synchronize_remote", return_value=remote),
            mock.patch.object(app.Transaction, "begin", return_value=tx),
            mock.patch.object(app, "apply_root_distribution", side_effect=lambda *_: events.append("root")),
            mock.patch.object(
                app,
                "apply_profile_distribution",
                side_effect=lambda *_args, **_kwargs: events.append(
                    "profile:rick"
                ),
            ),
            mock.patch.object(app, "apply_shared_working_tree", side_effect=lambda *_: events.append("shared:lifelog")),
            mock.patch.object(app, "build_dashboard_environment", return_value={"DASH": "value"}),
            mock.patch.object(app, "build_profile_environment", return_value={"GH_TOKEN": "token"}),
            mock.patch.object(app, "merge_env_file", side_effect=lambda path, *_: events.append(f"env:{path.parent.name}")),
            mock.patch.object(app, "_validate_installed_layout", side_effect=validate_installed),
        ):
            with self.assertRaisesRegex(ValidationError, "installed layout failed"):
                app.apply(Path("manifest.yaml"), io.StringIO("payload"))

        self.assertEqual(
            events,
            ["root", "profile:rick", "shared:lifelog", "env:data", "validate", "rollback"],
        )
        self.assertNotIn("commit", events)

    def test_public_validate_is_network_free_and_disallows_active_transaction(self) -> None:
        from hermes_bootstrap import app

        with (
            mock.patch.object(app, "load_manifest", return_value=self.manifest),
            mock.patch.object(app.Transaction, "recover_if_needed") as recover,
            mock.patch.object(app, "GitHubClient") as github,
            mock.patch.object(app, "_validate_installed_layout", return_value={"profiles": [], "repositories": []}) as installed,
        ):
            result = app.validate(Path("manifest.yaml"))

        self.assertEqual(result, {"status": "valid", "profiles": [], "repositories": []})
        installed.assert_called_once_with(self.manifest, allow_active_transaction=False)
        recover.assert_not_called()
        github.assert_not_called()

    def test_active_transaction_is_allowed_only_by_internal_installed_validation(self) -> None:
        from hermes_bootstrap import app

        self.write_valid_layout()
        tx = app.Transaction.begin(self.root)
        try:
            result = app._validate_installed_layout(
                self.manifest, allow_active_transaction=True
            )
            self.assertEqual(
                result, {"profiles": ["rick"], "repositories": ["lifelog"]}
            )
            with mock.patch.object(app, "load_manifest", return_value=self.manifest):
                with self.assertRaisesRegex(
                    ValidationError, "incomplete bootstrap transaction"
                ):
                    app.validate(Path("manifest.yaml"))
        finally:
            tx.rollback()

    def test_sync_repository_uses_process_then_safe_env_files_without_executing_them(self) -> None:
        from hermes_bootstrap import app

        root_env = self.root / ".env"
        root_env.write_text("GH_TOKEN='root-token'\n", encoding="utf-8")
        active = self.root / "profiles" / "rick"
        active.mkdir(parents=True)
        (active / ".env").write_text(
            "$(touch should-not-exist)\nGH_TOKEN='active-token'\n",
            encoding="utf-8",
        )
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

    def test_sync_profiles_uses_process_active_home_then_root_token_precedence(self) -> None:
        from hermes_bootstrap import app

        root_env = self.root / ".env"
        root_env.write_text("GH_TOKEN='root-token'\n", encoding="utf-8")
        active = self.root / "profiles" / "rick"
        active.mkdir(parents=True)
        (active / ".env").write_text(
            "$(touch should-not-exist)\nGH_TOKEN='active-token'\n",
            encoding="utf-8",
        )
        expected_report = ProfileSyncReport(dry_run=True, profiles=(), exit_code=0)
        cases = (
            (
                {"GH_TOKEN": "process-token", "HERMES_HOME": str(active)},
                "process-token",
            ),
            ({"HERMES_HOME": str(active)}, "active-token"),
            ({}, "root-token"),
        )

        for environ, expected_token in cases:
            with (
                self.subTest(expected_token=expected_token),
                mock.patch.object(app, "load_manifest", return_value=self.manifest),
                mock.patch.object(
                    app.profile_sync,
                    "synchronize_profiles",
                    return_value=expected_report,
                ) as sync,
            ):
                report = app.sync_profiles(
                    Path("manifest.yaml"), dry_run=True, environ=environ
                )

            self.assertIs(report, expected_report)
            auth = sync.call_args.args[1]
            self.assertEqual(auth.token, expected_token)
            self.assertEqual(
                sync.call_args.kwargs,
                {"dry_run": True},
            )
        self.assertFalse((active / "should-not-exist").exists())

    def test_sync_profiles_reports_missing_credentials_for_every_configured_profile(self) -> None:
        from hermes_bootstrap import app

        configured = manifest(self.root, ("alpha", "beta", "gamma"))
        with (
            mock.patch.object(app, "load_manifest", return_value=configured),
            mock.patch.object(app.profile_sync, "synchronize_profiles") as sync,
        ):
            report = app.sync_profiles(Path("manifest.yaml"), dry_run=False, environ={})

        self.assertEqual(report.exit_code, CredentialError.exit_code)
        self.assertEqual(
            [profile.name for profile in report.profiles],
            [profile.name for profile in configured.profiles],
        )
        self.assertTrue(
            all(
                profile.status == "failed"
                and profile.category == "credentials_unavailable"
                and profile.message == "GitHub credentials are unavailable"
                for profile in report.profiles
            )
        )
        sync.assert_not_called()

    def test_sync_profiles_sanitizes_repository_and_unexpected_failures_for_all_profiles(self) -> None:
        from hermes_bootstrap import app

        configured = manifest(self.root, ("alpha", "beta", "gamma"))
        token = "profile-sync-token-marker"
        (self.root / ".env").write_text(f"GH_TOKEN={token}\n", encoding="utf-8")

        for failure in (
            RepositoryError(token),
            RuntimeError(token),
        ):
            with (
                self.subTest(failure=type(failure).__name__),
                mock.patch.object(app, "load_manifest", return_value=configured),
                mock.patch.object(
                    app.profile_sync,
                    "synchronize_profiles",
                    side_effect=failure,
                ),
            ):
                report = app.sync_profiles(
                    Path("manifest.yaml"), dry_run=False, environ={}
                )

            self.assertEqual(report.exit_code, RepositoryError.exit_code)
            self.assertEqual(
                [profile.name for profile in report.profiles],
                [profile.name for profile in configured.profiles],
            )
            self.assertTrue(
                all(
                    profile.status == "failed"
                    and profile.category == "repository"
                    and profile.message == "profile synchronization failed"
                    for profile in report.profiles
                )
            )
            self.assertNotIn(token, json.dumps(report.as_dict()))
            self.assertIsNone(failure.__traceback__)
            self.assertIsNone(failure.__context__)

    def test_sync_profiles_reports_unsafe_runtime_and_token_files_as_credentials_unavailable(self) -> None:
        from hermes_bootstrap import app

        for scenario in ("unrelated", "symlink", "duplicate", "hardlink", "fifo"):
            with self.subTest(scenario=scenario), tempfile.TemporaryDirectory() as directory:
                root = Path(directory) / "data"
                root.mkdir()
                configured = manifest(root, ("alpha", "beta"))
                environ: dict[str, str] = {}
                if scenario == "unrelated":
                    unrelated = root.parent / "unrelated"
                    unrelated.mkdir()
                    environ["HERMES_HOME"] = str(unrelated)
                elif scenario == "symlink":
                    outside = root.parent / "outside"
                    outside.mkdir()
                    linked = root / "linked"
                    linked.symlink_to(outside, target_is_directory=True)
                    environ["HERMES_HOME"] = str(linked)
                elif scenario == "duplicate":
                    (root / ".env").write_text(
                        "GH_TOKEN=one\nGH_TOKEN=two\n", encoding="utf-8"
                    )
                elif scenario == "hardlink":
                    external = root.parent / "external.env"
                    external.write_text("GH_TOKEN=secret\n", encoding="utf-8")
                    os.link(external, root / ".env")
                else:
                    os.mkfifo(root / ".env")

                with (
                    mock.patch.object(app, "load_manifest", return_value=configured),
                    mock.patch.object(
                        app.profile_sync, "synchronize_profiles"
                    ) as sync,
                ):
                    report = app.sync_profiles(
                        Path("manifest.yaml"), dry_run=True, environ=environ
                    )

                self.assertEqual(report.exit_code, CredentialError.exit_code)
                self.assertEqual(
                    [profile.name for profile in report.profiles],
                    [profile.name for profile in configured.profiles],
                )
                self.assertTrue(
                    all(
                        profile.category == "credentials_unavailable"
                        for profile in report.profiles
                    )
                )
                sync.assert_not_called()

    def test_sync_repository_rejects_unrelated_or_symlinked_hermes_home(self) -> None:
        from hermes_bootstrap import app

        (self.root / ".env").write_text("GH_TOKEN=root-token\n", encoding="utf-8")
        unrelated = self.root.parent / "unrelated"
        unrelated.mkdir()
        escaped = self.root.parent / "escaped"
        escaped.mkdir()
        (self.root / "linked").symlink_to(escaped, target_is_directory=True)

        with mock.patch.object(app, "load_manifest", return_value=self.manifest):
            for runtime_home in (unrelated, self.root / "linked"):
                with self.subTest(runtime_home=runtime_home), self.assertRaises(CredentialError):
                    app.sync_repository(Path("manifest.yaml"), "lifelog", {"HERMES_HOME": str(runtime_home)})

    def test_apply_cleans_earlier_private_remote_stage_when_later_sync_fails(self) -> None:
        from hermes_bootstrap import app
        from hermes_bootstrap.filesystem import create_private_directory

        second = SharedRepository(
            "notes", "https://github.com/example/notes.git", "main",
            self.root / "shared" / "notes", "read-only", None, None,
        )
        configured = BootstrapManifest(
            self.manifest.schema_version, self.root, self.manifest.onepassword_items,
            self.manifest.root_distribution, self.manifest.profiles,
            (*self.manifest.shared_repositories, second),
        )
        private_parent = self.root / "shared"
        private_parent.mkdir()
        private_directory = create_private_directory(
            private_parent,
            prefix=".hermes-repository-",
        )
        private = private_directory.path
        sentinel = self.root / "local-sentinel"
        sentinel.write_bytes(b"unchanged")
        sentinel.chmod(0o640)
        first = RemoteSyncResult(
            "lifelog",
            "a" * 40,
            False,
            private,
            private_directory,
        )

        with (
            mock.patch.object(app, "load_manifest", return_value=configured),
            mock.patch.object(app.Transaction, "recover_if_needed"),
            mock.patch.object(app, "read_secret_payload", return_value=mock.Mock(github_token="token", redactor=SecretRedactor(("token",)))),
            mock.patch.object(app, "_validate_remote_credentials"),
            mock.patch.object(app, "_validate_profile_credentials"),
            mock.patch.object(app, "stage_distribution", return_value=mock.Mock()),
            mock.patch.object(app, "synchronize_remote", side_effect=(first, ApplyError("second failed"))),
            mock.patch.object(app.Transaction, "begin") as begin,
        ):
            with self.assertRaisesRegex(ApplyError, "second failed"):
                app.apply(Path("manifest.yaml"), io.StringIO("payload"))
        self.assertFalse(private.exists())
        self.assertEqual(sentinel.read_bytes(), b"unchanged")
        self.assertEqual(stat.S_IMODE(sentinel.stat().st_mode), 0o640)
        begin.assert_not_called()

    def test_remote_cleanup_failure_wins_and_never_removes_canonical_or_legacy(self) -> None:
        from hermes_bootstrap import app
        from hermes_bootstrap.filesystem import create_private_directory

        repo = self.manifest.shared_repositories[0]
        repo.target.parent.mkdir()
        private_directory = create_private_directory(
            repo.target.parent,
            prefix=".hermes-repository-",
        )
        private = private_directory.path
        results = [
            (repo, RemoteSyncResult(repo.name, "a" * 40, False, repo.target)),
            (repo, RemoteSyncResult(repo.name, "a" * 40, False, repo.legacy_target)),
            (
                repo,
                RemoteSyncResult(
                    repo.name,
                    "a" * 40,
                    False,
                    private,
                    private_directory,
                ),
            ),
        ]
        with mock.patch.object(
            private_directory,
            "cleanup",
            return_value=False,
        ) as remove:
            self.assertFalse(app._cleanup_apply_resources(None, results, self.root))
        remove.assert_called_once_with()

    def test_apply_surfaces_strict_scratch_cleanup_failure(self) -> None:
        from hermes_bootstrap import app

        with (
            mock.patch.object(app, "load_manifest", return_value=self.manifest),
            mock.patch.object(app.Transaction, "recover_if_needed"),
            mock.patch.object(app, "read_secret_payload", return_value=mock.Mock(github_token="token", redactor=SecretRedactor(("token",)))),
            mock.patch.object(app, "_validate_remote_credentials"),
            mock.patch.object(app, "_validate_profile_credentials"),
            mock.patch.object(app, "stage_distribution", side_effect=ApplyError("stage failed")),
            mock.patch.object(
                app.PrivateDirectory,
                "cleanup",
                return_value=False,
            ),
        ):
            with self.assertRaisesRegex(ApplyError, "clean bootstrap staging"):
                app.apply(Path("manifest.yaml"), io.StringIO("payload"))

    def test_outer_scratch_anomaly_is_retained_and_cleanup_error_is_redacted(
        self,
    ) -> None:
        from hermes_bootstrap import app

        sensitive_marker = "outer-scratch-sensitive-marker"
        scratch_path: Path | None = None

        def leave_anomaly(_manifest, scratch, *, allow_missing):
            nonlocal scratch_path
            self.assertIs(_manifest, self.manifest)
            self.assertTrue(allow_missing)
            scratch_path = scratch
            os.mkfifo(scratch / "retained-fifo")
            raise RepositoryError(sensitive_marker)

        with (
            mock.patch.object(app, "load_manifest", return_value=self.manifest),
            mock.patch.object(app.Transaction, "recover_if_needed"),
            mock.patch.object(
                app,
                "read_secret_payload",
                return_value=mock.Mock(
                    github_token="token",
                    redactor=SecretRedactor(("token",)),
                ),
            ),
            mock.patch.object(app, "_validate_remote_credentials"),
            mock.patch.object(app, "_validate_profile_credentials"),
            mock.patch.object(
                app,
                "prepare_profile_snapshots",
                side_effect=leave_anomaly,
            ),
        ):
            with self.assertRaisesRegex(
                ApplyError,
                "could not clean bootstrap staging resources",
            ) as caught:
                app.apply(Path("manifest.yaml"), io.StringIO("payload"))

        self.assertIsNotNone(scratch_path)
        assert scratch_path is not None
        self.assertTrue((scratch_path / "retained-fifo").exists())
        self.assertNotIn(sensitive_marker, repr(caught.exception))

    def test_every_local_failpoint_restores_exact_state_and_retains_remote_result(self) -> None:
        from hermes_bootstrap import app

        failpoints = (
            "root-apply",
            "profile-apply:rick",
            "shared-apply:lifelog",
            "env-merge:default",
            "env-merge:rick",
            "final-validation",
            "commit-cleanup",
        )
        for selected in failpoints:
            with self.subTest(selected=selected), tempfile.TemporaryDirectory() as directory:
                data_root = Path(directory) / "data"
                data_root.mkdir()
                configured = manifest(data_root)
                root_file = data_root / "managed-root"
                root_file.write_bytes(b"root-before")
                root_file.chmod(0o640)
                profile_root = data_root / "profiles" / "rick"
                profile_root.mkdir(parents=True)
                profile_link = profile_root / "managed-link"
                profile_link.symlink_to("original-target")
                root_env = data_root / ".env"
                root_env.write_bytes(b"ROOT=before\n")
                root_env.chmod(0o600)
                profile_env = profile_root / ".env"
                shared_marker = data_root / "shared-local"
                remote_marker = Path(directory) / "remote-result"
                prepared = PreparedProfiles(
                    (mock.Mock(declaration=configured.profiles[0]),),
                    (),
                )
                profile_report = ProfileSyncReport(
                    dry_run=False,
                    profiles=(
                        ProfileSyncResult(
                            "rick",
                            "unchanged",
                            "1" * 40,
                            "snapshot-rick",
                            ProfileDiff(),
                            "unchanged",
                            "safe",
                        ),
                    ),
                    exit_code=0,
                )

                def stage(source: DistributionSource, _scratch: Path, _auth: GitAuth):
                    return mock.Mock(declaration=source)

                def sync(repo: SharedRepository, _auth: GitAuth):
                    remote_marker.write_bytes(b"pushed")
                    return RemoteSyncResult(repo.name, "a" * 40, True, repo.target)

                def root_apply(_stage: object, _root: Path, tx: object) -> None:
                    tx.snapshot(root_file)
                    root_file.write_bytes(b"root-after")
                    root_file.chmod(0o600)

                def profile_apply(
                    _stage: object,
                    _root: Path,
                    tx: object,
                    **_kwargs: object,
                ) -> None:
                    tx.snapshot(profile_link)
                    profile_link.unlink()
                    profile_link.write_bytes(b"not-a-link")

                def shared_apply(_repo: object, _result: object, tx: object) -> None:
                    tx.snapshot(shared_marker)
                    shared_marker.write_bytes(b"created")

                def merge(path: Path, *_args: object) -> None:
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_bytes(b"CHANGED=yes\n")
                    path.chmod(0o600)

                def failpoint(name: str) -> None:
                    if name == selected:
                        raise ApplyError("injected local failure")

                with (
                    mock.patch.object(app, "load_manifest", return_value=configured),
                    mock.patch.object(app, "read_secret_payload", return_value=mock.Mock(github_token="token", redactor=SecretRedactor(("token",)))),
                    mock.patch.object(app, "_validate_remote_credentials"),
                    mock.patch.object(app, "_validate_profile_credentials"),
                    mock.patch.object(
                        app,
                        "prepare_profile_snapshots",
                        return_value=prepared,
                    ),
                    mock.patch.object(
                        app.profile_sync,
                        "synchronize_prepared_profiles",
                        return_value=profile_report,
                    ),
                    mock.patch.object(app, "stage_distribution", side_effect=stage),
                    mock.patch.object(app, "synchronize_remote", side_effect=sync),
                    mock.patch.object(app, "apply_root_distribution", side_effect=root_apply),
                    mock.patch.object(app, "apply_profile_distribution", side_effect=profile_apply),
                    mock.patch.object(app, "apply_shared_working_tree", side_effect=shared_apply),
                    mock.patch.object(app, "build_dashboard_environment", return_value={"DASH": "value"}),
                    mock.patch.object(app, "build_profile_environment", return_value={"GH_TOKEN": "token"}),
                    mock.patch.object(app, "merge_env_file", side_effect=merge),
                    mock.patch.object(app, "_validate_installed_layout"),
                    mock.patch.object(app, "_failpoint", side_effect=failpoint),
                ):
                    with self.assertRaisesRegex(ApplyError, "injected local failure"):
                        app.apply(Path("manifest.yaml"), io.StringIO("payload"))

                self.assertEqual(root_file.read_bytes(), b"root-before")
                self.assertEqual(stat.S_IMODE(root_file.stat().st_mode), 0o640)
                self.assertTrue(profile_link.is_symlink())
                self.assertEqual(os.readlink(profile_link), "original-target")
                self.assertEqual(root_env.read_bytes(), b"ROOT=before\n")
                self.assertEqual(stat.S_IMODE(root_env.stat().st_mode), 0o600)
                self.assertFalse(profile_env.exists())
                self.assertFalse(shared_marker.exists())
                self.assertEqual(remote_marker.read_bytes(), b"pushed")
                self.assertFalse(any(data_root.glob(".hermes-bootstrap-*")))

    def test_sync_repository_rejects_duplicate_or_unsafe_token_files(self) -> None:
        from hermes_bootstrap import app

        (self.root / ".env").write_text("GH_TOKEN=one\nGH_TOKEN=two\n", encoding="utf-8")
        with mock.patch.object(app, "load_manifest", return_value=self.manifest):
            with self.assertRaises(CredentialError):
                app.sync_repository(Path("manifest.yaml"), "lifelog", {})

    def test_sync_repository_rejects_a_hardlinked_token_file(self) -> None:
        from hermes_bootstrap import app

        external = self.root.parent / "external-token.env"
        external.write_text("GH_TOKEN=external-token-marker\n", encoding="utf-8")
        os.link(external, self.root / ".env")

        with (
            mock.patch.object(app, "load_manifest", return_value=self.manifest),
            mock.patch.object(app, "synchronize_named_repository") as sync,
            self.assertRaises(CredentialError) as caught,
        ):
            app.sync_repository(Path("manifest.yaml"), "lifelog", {})

        self.assertNotIn("external-token-marker", str(caught.exception))
        sync.assert_not_called()

    def test_sync_repository_rejects_a_fifo_token_file_without_blocking(self) -> None:
        from hermes_bootstrap import app

        os.mkfifo(self.root / ".env")

        with (
            mock.patch.object(app, "load_manifest", return_value=self.manifest),
            mock.patch.object(app, "synchronize_named_repository") as sync,
            self.assertRaises(CredentialError),
        ):
            app.sync_repository(Path("manifest.yaml"), "lifelog", {})

        sync.assert_not_called()

    def test_read_env_token_closes_the_anchored_parent_when_the_file_is_absent(self) -> None:
        from hermes_bootstrap import app

        opened: list[int] = []
        closed: list[int] = []
        real_close = os.close

        def open_parent(path: Path) -> int:
            descriptor = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
            opened.append(descriptor)
            return descriptor

        def record_close(descriptor: int) -> None:
            closed.append(descriptor)
            real_close(descriptor)

        with (
            mock.patch.object(app, "open_absolute_directory", side_effect=open_parent),
            mock.patch.object(app.os, "close", side_effect=record_close),
        ):
            self.assertIsNone(app._read_env_token(self.root / "missing.env"))

        self.assertEqual(closed, opened)

    def test_sync_repository_rejects_a_token_file_beneath_a_swapped_ancestor(self) -> None:
        from hermes_bootstrap import app

        active = self.root / "profiles" / "default"
        active.mkdir(parents=True)
        (active / ".env").write_text("GH_TOKEN=original-token\n", encoding="utf-8")
        held = self.root / "held-runtime"
        outside = self.root / "outside-runtime"
        outside.mkdir()
        (outside / ".env").write_text("GH_TOKEN=attacker-token-marker\n", encoding="utf-8")

        def swap_runtime_ancestor(_data_root: Path, _candidate: Path) -> bool:
            active.rename(held)
            active.symlink_to(outside, target_is_directory=True)
            return True

        with (
            mock.patch.object(app, "load_manifest", return_value=self.manifest),
            mock.patch.object(app, "_safe_runtime_home", side_effect=swap_runtime_ancestor),
            mock.patch.object(app, "synchronize_named_repository") as sync,
            self.assertRaises(CredentialError) as caught,
        ):
            app.sync_repository(
                Path("manifest.yaml"),
                "lifelog",
                {"HERMES_HOME": str(active)},
            )

        self.assertNotIn("attacker-token-marker", str(caught.exception))
        sync.assert_not_called()

    def test_validate_fails_closed_for_missing_state_without_leaking_paths(self) -> None:
        from hermes_bootstrap import app

        with mock.patch.object(app, "load_manifest", return_value=self.manifest):
            with self.assertRaises(ValidationError) as raised:
                app.validate(Path("manifest.yaml"))
        self.assertNotIn(str(self.root), str(raised.exception))

    def test_profile_validation_rejects_incompatible_hermes_and_missing_owned_target(self) -> None:
        from hermes_bootstrap import app

        target = self.write_installed_profile(hermes_requires=">99.0.0")
        (target / "config.yaml").write_text("config\n", encoding="utf-8")
        with self.assertRaises(ValidationError):
            app._validate_profiles(self.manifest)

        (target / "distribution.yaml").unlink()
        (target / "config.yaml").unlink()
        self.write_installed_profile()
        with self.assertRaises(ValidationError):
            app._validate_profiles(self.manifest)

    def test_profile_validation_rejects_nested_symlink_and_external_hardlink(self) -> None:
        from hermes_bootstrap import app

        target = self.write_installed_profile(owned=["assets"])
        assets = target / "assets"
        assets.mkdir()
        outside = self.root.parent / "outside"
        outside.write_text("outside\n", encoding="utf-8")
        (assets / "link").symlink_to(outside)
        with self.assertRaises(ValidationError):
            app._validate_profiles(self.manifest)

        (assets / "link").unlink()
        os.link(outside, assets / "hardlink")
        with self.assertRaises(ValidationError):
            app._validate_profiles(self.manifest)

    def test_profile_validation_rejects_symlinked_owned_path_ancestor(self) -> None:
        from hermes_bootstrap import app

        self.write_installed_profile(owned=["assets/payload.txt"])
        outside = self.root.parent / "outside-assets"
        outside.mkdir()
        (outside / "payload.txt").write_text("outside\n", encoding="utf-8")
        (self.root / "profiles" / "rick" / "assets").symlink_to(
            outside, target_is_directory=True
        )

        with self.assertRaises(ValidationError):
            app._validate_profiles(self.manifest)

    def test_root_state_rejects_symlinked_bootstrap_ancestor(self) -> None:
        from hermes_bootstrap import app

        outside = self.root.parent / "outside-bootstrap"
        outside.mkdir()
        state = outside / "root-distribution-state.json"
        state.write_text(
            json.dumps(
                {
                    "source": self.manifest.root_distribution.source,
                    "ref": "main",
                    "commit": "a" * 40,
                    "version": "0.1.0",
                    "distribution_owned": ["config.yaml"],
                }
            ),
            encoding="utf-8",
        )
        (self.root / "config.yaml").write_text("config\n", encoding="utf-8")
        (self.root / ".bootstrap").symlink_to(outside, target_is_directory=True)
        with self.assertRaises(ValidationError):
            app._validate_root_state(self.manifest)

    def test_repository_validation_rejects_credential_query_and_port_remotes(self) -> None:
        from hermes_bootstrap import app

        for remote in (
            "https://user:password@github.com/example/lifelog.git",
            "https://github.com/example/lifelog.git?token=value",
            "https://github.com:8443/example/lifelog.git",
        ):
            with self.subTest(remote=remote):
                if (self.root / "shared").exists():
                    import shutil

                    shutil.rmtree(self.root / "shared")
                legacy = self.manifest.shared_repositories[0].legacy_target
                assert legacy is not None
                if legacy.is_symlink():
                    legacy.unlink()
                self.write_repository_metadata(remote)
                with self.assertRaises(ValidationError):
                    app._validate_repositories(self.manifest)

    def test_repository_validation_rejects_a_remaining_legacy_path(self) -> None:
        from hermes_bootstrap import app

        self.write_repository_metadata(self.manifest.shared_repositories[0].source)
        legacy = self.manifest.shared_repositories[0].legacy_target
        assert legacy is not None
        legacy.parent.mkdir(parents=True)
        legacy.symlink_to(os.path.relpath(self.manifest.shared_repositories[0].target, legacy.parent))

        with self.assertRaises(ValidationError):
            app._validate_repositories(self.manifest)

    def test_installed_layout_validation_accepts_valid_owned_and_user_paths_without_network(self) -> None:
        from hermes_bootstrap import app

        self.write_valid_layout()
        target = self.root / "profiles" / "rick"
        user_owned = target / "memories"
        user_owned.mkdir()
        (user_owned / "outside-link").symlink_to(self.root.parent)

        with mock.patch.object(app, "GitHubClient") as github:
            result = app._validate_installed_layout(
                self.manifest, allow_active_transaction=False
            )

        self.assertEqual(result, {"profiles": ["rick"], "repositories": ["lifelog"]})
        github.assert_not_called()

    def test_installed_layout_validation_preserves_unmanaged_profile_entries(self) -> None:
        from hermes_bootstrap import app

        self.write_valid_layout()
        profiles = self.root / "profiles"
        extra_profile = profiles / "local"
        extra_profile.mkdir()
        (extra_profile / "notes.txt").write_text("keep me\n", encoding="utf-8")
        metadata = profiles / ".DS_Store"
        metadata.write_bytes(b"finder metadata")

        result = app._validate_installed_layout(
            self.manifest, allow_active_transaction=False
        )

        self.assertEqual(result, {"profiles": ["rick"], "repositories": ["lifelog"]})
        self.assertEqual((extra_profile / "notes.txt").read_text(encoding="utf-8"), "keep me\n")
        self.assertEqual(metadata.read_bytes(), b"finder metadata")

        (profiles / "rick" / "config.yaml").unlink()
        with self.assertRaisesRegex(
            ValidationError, "installed distribution target is invalid"
        ):
            app._validate_installed_layout(
                self.manifest, allow_active_transaction=False
            )

    def test_installed_layout_validation_rejects_empty_required_values(self) -> None:
        from hermes_bootstrap import app

        self.write_valid_layout()
        root_env = self.root / ".env"
        valid = root_env.read_text(encoding="utf-8")
        for key in sorted(app._MANAGED_ENV_KEYS):
            with self.subTest(key=key):
                content = "\n".join(
                    f"{key}=" if line.startswith(f"{key}=") else line
                    for line in valid.splitlines()
                )
                root_env.write_text(content + "\n", encoding="utf-8")

                with self.assertRaisesRegex(
                    ValidationError, "installed environment file is invalid"
                ):
                    app._validate_installed_layout(
                        self.manifest, allow_active_transaction=False
                    )

    def test_installed_layout_validation_rejects_mismatched_github_aliases_without_secret_details(self) -> None:
        from hermes_bootstrap import app

        self.write_valid_layout()
        root_env = self.root / ".env"
        marker = "github-mismatch-secret-marker"
        content = root_env.read_text(encoding="utf-8").replace(
            "GITHUB_TOKEN=github-token", f"GITHUB_TOKEN={marker}"
        )
        root_env.write_text(content, encoding="utf-8")

        with self.assertRaisesRegex(
            ValidationError, "installed environment file is invalid"
        ) as raised:
            app._validate_installed_layout(
                self.manifest, allow_active_transaction=False
            )
        self.assertNotIn(marker, str(raised.exception))
        self.assertNotIn(marker, repr(raised.exception))

    def test_installed_layout_validation_rejects_invalid_slack_token_formats_without_secret_details(self) -> None:
        from hermes_bootstrap import app

        self.write_valid_layout()
        root_env = self.root / ".env"
        valid = root_env.read_text(encoding="utf-8")
        invalid_values = {
            "SLACK_BOT_TOKEN": "xapp-wrong-role-secret-marker",
            "SLACK_APP_TOKEN": "xoxb-wrong-role-secret-marker",
        }
        for key, marker in invalid_values.items():
            with self.subTest(key=key):
                content = "\n".join(
                    f"{key}={marker}" if line.startswith(f"{key}=") else line
                    for line in valid.splitlines()
                )
                root_env.write_text(content + "\n", encoding="utf-8")

                with self.assertRaisesRegex(
                    ValidationError, "installed environment file is invalid"
                ) as raised:
                    app._validate_installed_layout(
                        self.manifest, allow_active_transaction=False
                    )
                self.assertNotIn(marker, str(raised.exception))
                self.assertNotIn(marker, repr(raised.exception))

    def test_installed_layout_validation_rejects_weak_root_runtime_secrets(self) -> None:
        from hermes_bootstrap import app

        self.write_valid_layout()
        root_env = self.root / ".env"
        valid = root_env.read_text(encoding="utf-8")
        for key in (
            "API_SERVER_KEY",
            "HERMES_DASHBOARD_BASIC_AUTH_SECRET",
        ):
            with self.subTest(key=key):
                content = "\n".join(
                    f"{key}=aaaaaaaaaaaaaaaa" if line.startswith(f"{key}=") else line
                    for line in valid.splitlines()
                )
                root_env.write_text(content + "\n", encoding="utf-8")

                with self.assertRaisesRegex(
                    ValidationError, "installed environment file is invalid"
                ):
                    app._validate_installed_layout(
                        self.manifest, allow_active_transaction=False
                    )

    def test_git_head_rejects_symbolic_ref_symlink_escape(self) -> None:
        from hermes_bootstrap import app

        git = self.root / "checkout" / ".git"
        ref_parent = git / "refs" / "heads"
        ref_parent.mkdir(parents=True)
        (git / "HEAD").write_text("ref: refs/heads/main\n", encoding="ascii")
        outside = self.root.parent / "outside-object-id"
        outside.write_text("a" * 40 + "\n", encoding="ascii")
        (ref_parent / "main").symlink_to(outside)

        with self.assertRaises(ValidationError):
            app._git_head(git)

        (ref_parent / "main").unlink()
        os.link(outside, ref_parent / "main")
        with self.assertRaises(ValidationError):
            app._git_head(git)

        (ref_parent / "main").unlink()
        ref_parent.rmdir()
        outside_refs = self.root.parent / "outside-refs"
        outside_refs.mkdir()
        (outside_refs / "main").write_text("a" * 40 + "\n", encoding="ascii")
        ref_parent.symlink_to(outside_refs, target_is_directory=True)
        with self.assertRaises(ValidationError):
            app._git_head(git)

    def test_git_head_rejects_invalid_components_and_unsafe_ref_objects(self) -> None:
        from hermes_bootstrap import app

        cases = (
            ("refs//heads/main", ("refs", "heads", "main")),
            (r"refs/heads\main", ("refs", r"heads\main")),
            ("refs/heads/../main", ("refs", "main")),
        )
        for symbolic_ref, target_parts in cases:
            with self.subTest(symbolic_ref=symbolic_ref), tempfile.TemporaryDirectory() as directory:
                git = Path(directory) / ".git"
                git.mkdir()
                (git / "HEAD").write_text(f"ref: {symbolic_ref}\n", encoding="ascii")
                target = git.joinpath(*target_parts)
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text("a" * 40 + "\n", encoding="ascii")
                with self.assertRaises(ValidationError):
                    app._git_head(git)

        with tempfile.TemporaryDirectory() as directory:
            git = Path(directory) / ".git"
            ref = git / "refs" / "heads" / "main"
            ref.parent.mkdir(parents=True)
            (git / "HEAD").write_text("ref: refs/heads/main\n", encoding="ascii")
            with socket.socket(socket.AF_UNIX) as listener:
                listener.bind(str(ref))
                with self.assertRaises(ValidationError):
                    app._git_head(git)

    def test_git_head_accepts_detached_and_safe_symbolic_heads(self) -> None:
        from hermes_bootstrap import app

        git = self.root / "checkout" / ".git"
        git.mkdir(parents=True)
        detached = "a" * 40
        (git / "HEAD").write_text(detached + "\n", encoding="ascii")
        self.assertEqual(app._git_head(git), detached)

        symbolic = "b" * 64
        ref = git / "refs" / "heads" / "main"
        ref.parent.mkdir(parents=True)
        ref.write_text(symbolic + "\n", encoding="ascii")
        (git / "HEAD").write_text("ref: refs/heads/main\n", encoding="ascii")
        self.assertEqual(app._git_head(git), symbolic)

    def test_transaction_store_rejects_dangling_symlink_and_unsafe_objects(self) -> None:
        from hermes_bootstrap import app

        bootstrap = self.root / ".bootstrap"
        bootstrap.mkdir()
        store = bootstrap / "transactions"
        store.symlink_to(self.root / "missing-transactions", target_is_directory=True)
        self.assertTrue(os.path.lexists(store))
        with self.assertRaises(ValidationError):
            app._validate_no_transaction(self.root)

        store.unlink()
        store.write_text("not a directory\n", encoding="utf-8")
        with self.assertRaises(ValidationError):
            app._validate_no_transaction(self.root)

    def test_transaction_store_allows_a_truly_absent_store(self) -> None:
        from hermes_bootstrap import app

        self.assertFalse(os.path.lexists(self.root / ".bootstrap" / "transactions"))
        app._validate_no_transaction(self.root)

    def test_transaction_store_allows_only_a_safe_lock_file(self) -> None:
        from hermes_bootstrap import app

        lock = self.transaction_lock_path()
        lock.write_bytes(b"")
        lock.chmod(0o600)

        app._validate_no_transaction(self.root)

    def test_transaction_store_rejects_lock_directory(self) -> None:
        from hermes_bootstrap import app

        self.transaction_lock_path().mkdir()

        with self.assertRaises(ValidationError):
            app._validate_no_transaction(self.root)

    def test_transaction_store_rejects_lock_symlink(self) -> None:
        from hermes_bootstrap import app

        target = self.root.parent / "lock-target"
        target.write_bytes(b"")
        target.chmod(0o600)
        self.transaction_lock_path().symlink_to(target)

        with self.assertRaises(ValidationError):
            app._validate_no_transaction(self.root)

    def test_transaction_store_rejects_hardlinked_lock(self) -> None:
        from hermes_bootstrap import app

        target = self.root.parent / "lock-target"
        target.write_bytes(b"")
        target.chmod(0o600)
        os.link(target, self.transaction_lock_path())

        with self.assertRaises(ValidationError):
            app._validate_no_transaction(self.root)

    def test_transaction_store_rejects_special_lock(self) -> None:
        from hermes_bootstrap import app

        lock = self.transaction_lock_path()
        with socket.socket(socket.AF_UNIX) as listener:
            listener.bind(str(lock))
            with self.assertRaises(ValidationError):
                app._validate_no_transaction(self.root)

    def test_transaction_store_rejects_lock_with_wrong_mode(self) -> None:
        from hermes_bootstrap import app

        lock = self.transaction_lock_path()
        lock.write_bytes(b"")
        lock.chmod(0o640)

        with self.assertRaises(ValidationError):
            app._validate_no_transaction(self.root)
