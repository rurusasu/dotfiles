"""Repeatable end-to-end coverage for the Hermes bootstrap runtime."""

from __future__ import annotations

import io
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import threading
import unittest
from contextlib import contextmanager
from dataclasses import replace
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Iterator
from unittest import mock


BOOTSTRAP_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(BOOTSTRAP_ROOT))

from hermes_bootstrap import app
from hermes_bootstrap.errors import ApplyError, CredentialError, RepositoryError
from hermes_bootstrap.github import GitHubClient
from hermes_bootstrap.manifest import load_manifest
from hermes_bootstrap.models import BootstrapManifest, DistributionSource, SharedRepository
from hermes_bootstrap.payload import SCHEMA_VERSION


FIXTURE_TOKEN = "fixture-token-only"
API_URL_ENV = "HERMES_BOOTSTRAP_GITHUB_API_URL"
PRODUCTION_MANIFEST = BOOTSTRAP_ROOT.parent / "bootstrap-manifest.yaml"
PROFILE_NAMES = ("rick", "hoffman", "risarisa")


def run_git(*arguments: str, cwd: Path | None = None) -> str:
    completed = subprocess.run(
        ("git", *arguments),
        cwd=cwd,
        check=True,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    return completed.stdout.strip()


class FixtureGitHub:
    """Minimal loopback API which never records bearer credentials."""

    def __init__(self, identities: set[tuple[str, str]]) -> None:
        self.identities = identities
        self.server: ThreadingHTTPServer | None = None
        self.thread: threading.Thread | None = None

    def __enter__(self) -> "FixtureGitHub":
        identities = self.identities

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, _format: str, *_args: object) -> None:
                return

            def do_GET(self) -> None:  # noqa: N802
                authorized = self.headers.get("Authorization") == f"Bearer {FIXTURE_TOKEN}"
                if not authorized:
                    self.send_response(401)
                    self.send_header("Content-Length", "0")
                    self.end_headers()
                    return
                if self.path == "/user":
                    payload: dict[str, object] = {"login": "fixture"}
                elif self.path.startswith("/repos/"):
                    parts = self.path.split("/")
                    identity = (parts[2], parts[3]) if len(parts) == 4 else None
                    if identity not in identities:
                        self.send_response(404)
                        self.send_header("Content-Length", "0")
                        self.end_headers()
                        return
                    payload = {"full_name": f"{identity[0]}/{identity[1]}", "permissions": {"pull": True}}
                else:
                    self.send_response(404)
                    self.send_header("Content-Length", "0")
                    self.end_headers()
                    return
                body = json.dumps(payload, sort_keys=True).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        return self

    @property
    def url(self) -> str:
        assert self.server is not None
        host, port = self.server.server_address
        return f"http://{host}:{port}"

    def __exit__(self, *_args: object) -> None:
        assert self.server is not None and self.thread is not None
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)
        if self.thread.is_alive():
            raise AssertionError("fixture GitHub server did not stop")


class BootstrapFlowTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.fixture_root = Path(self.temporary.name)
        self.data_root = self.fixture_root / "data"
        self.data_root.mkdir()
        self.remotes = self.fixture_root / "remotes"
        self.seeds = self.fixture_root / "seeds"
        self.remotes.mkdir()
        self.seeds.mkdir()
        self.source_remotes: dict[str, Path] = {}
        self.source_identities: dict[str, tuple[str, str]] = {}
        self._create_sources()
        self.manifest = self._local_manifest()
        self._write_runtime_sentinels()

    def tearDown(self) -> None:
        self._assert_no_temporary_resources()

    def _create_sources(self) -> None:
        self._create_distribution(
            "root",
            {
                "root-distribution.yaml": self._root_manifest(["config.yaml", "retired.md"]),
                "config.yaml": "root: initial\n",
                "retired.md": "retire me\n",
            },
        )
        for profile in PROFILE_NAMES:
            self._create_distribution(
                profile,
                {
                    "distribution.yaml": self._profile_manifest(profile),
                    "config.yaml": f"profile: {profile}-initial\n",
                    "SOUL.md": f"{profile} initial\n",
                },
            )
        self._create_distribution("lifelog", {"README.md": "initial lifelog\n"})

    def _create_distribution(self, name: str, files: dict[str, str]) -> None:
        remote = self.remotes / f"{name}.git"
        seed = self.seeds / name
        run_git("init", "--bare", str(remote))
        run_git("init", "--initial-branch=main", str(seed))
        run_git("config", "user.name", "Fixture", cwd=seed)
        run_git("config", "user.email", "fixture@example.test", cwd=seed)
        self._write_files(seed, files)
        run_git("add", "-A", cwd=seed)
        run_git("commit", "-m", "initial fixture", cwd=seed)
        run_git("remote", "add", "origin", str(remote), cwd=seed)
        run_git("push", "origin", "main", cwd=seed)
        self.source_remotes[name] = remote
        self.source_identities[str(remote)] = ("fixture", name)

    def _local_manifest(self) -> BootstrapManifest:
        parsed = load_manifest(PRODUCTION_MANIFEST)
        root = replace(parsed.root_distribution, source=str(self.source_remotes["root"]), target=self.data_root)
        profiles = tuple(
            replace(
                source,
                source=str(self.source_remotes[source.name]),
                target=self.data_root / "profiles" / source.name,
            )
            for source in parsed.profiles
        )
        repositories = tuple(
            replace(
                repository,
                source=str(self.source_remotes[repository.name]),
                target=self.data_root / "shared" / repository.name,
                legacy_target=self.data_root / "core" / repository.name,
            )
            for repository in parsed.shared_repositories
        )
        return replace(parsed, data_root=self.data_root, root_distribution=root, profiles=profiles, shared_repositories=repositories)

    def _write_runtime_sentinels(self) -> None:
        self._write_files(
            self.data_root,
            {
                "memories/root.txt": "root memory\n",
                "sessions/root.txt": "root session\n",
                "cron/output/runtime.txt": "root cron output\n",
                "cron/state/runtime.txt": "root cron state\n",
                ".env": "# root comment\nCUSTOM_ROOT=keep\nGH_TOKEN=stale\nGH_TOKEN=duplicate\nHERMES_DASHBOARD_BASIC_AUTH_PASSWORD=plaintext\n",
            },
        )
        for profile in PROFILE_NAMES:
            self._write_files(
                self.data_root / "profiles" / profile,
                {
                    "memories/runtime.txt": f"{profile} memory\n",
                    "sessions/runtime.txt": f"{profile} session\n",
                    ".env": f"# {profile} comment\nCUSTOM_{profile.upper()}=keep\n",
                },
            )

    @staticmethod
    def _root_manifest(owned: list[str]) -> str:
        return "\n".join(
            [
                "schema_version: 1",
                "name: default",
                "version: 0.1.0",
                "hermes_requires: '>=0.18.2'",
                "distribution_owned:",
                *(f"  - {path}" for path in owned),
                "",
            ]
        )

    @staticmethod
    def _profile_manifest(name: str) -> str:
        return "\n".join(
            [
                f"name: {name}",
                "version: 0.1.0",
                "hermes_requires: '>=0.18.2'",
                "distribution_owned:",
                "  - config.yaml",
                "  - SOUL.md",
                "",
            ]
        )

    @staticmethod
    def _write_files(root: Path, files: dict[str, str]) -> None:
        for relative, contents in files.items():
            path = root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(contents, encoding="utf-8")

    def _commit(self, name: str, files: dict[str, str | None], message: str) -> str:
        seed = self.seeds[name]
        for relative, contents in files.items():
            path = seed / relative
            if contents is None:
                path.unlink()
            else:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(contents, encoding="utf-8")
        run_git("add", "-A", cwd=seed)
        run_git("commit", "-m", message, cwd=seed)
        run_git("push", "origin", "main", cwd=seed)
        return run_git("rev-parse", "HEAD", cwd=seed)

    def _payload(self, token: str = FIXTURE_TOKEN) -> io.StringIO:
        records: list[dict[str, object]] = [{"type": "header", "schema_version": SCHEMA_VERSION}]
        values = {
            "dashboard": {"username": "fixture-user", "password": "fixture-password"},
            "github": {"credential": token},
            "slack_default": {"bot_token": "default-bot", "app_token": "default-app", "allowed_users": "UDEFAULT"},
            "slack_rick": {"bot_token": "rick-bot", "app_token": "rick-app", "allowed_users": "URICK"},
            "slack_hoffman": {"bot_token": "hoffman-bot", "app_token": "hoffman-app", "allowed_users": "UHOFFMAN"},
            "slack_risarisa": {"bot_token": "risarisa-bot", "app_token": "risarisa-app", "allowed_users": "URISARISA"},
        }
        for item in self.manifest.onepassword_items:
            fields = [
                {"label": field.labels[0], "value": values[item.key][field.canonical_name]}
                for field in item.fields
            ]
            records.append({"type": "item", "key": item.key, "item": {"id": f"fixture-{item.key}", "fields": fields}})
        records.append({"type": "end"})
        return io.StringIO("".join(json.dumps(record, sort_keys=True) + "\n" for record in records))

    @contextmanager
    def _patched_runtime(self) -> Iterator[None]:
        with FixtureGitHub(set(self.source_identities.values())) as github:
            def client_factory(auth: object) -> GitHubClient:
                return GitHubClient(auth, api_base=os.environ[API_URL_ENV])  # type: ignore[arg-type]

            with (
                mock.patch.object(app, "load_manifest", return_value=self.manifest),
                mock.patch.object(app, "GitHubClient", side_effect=client_factory),
                mock.patch.object(app, "_source_identity", side_effect=self.source_identities.__getitem__),
                mock.patch("hermes_bootstrap.envfiles.hash_password", return_value="fixture-password-hash"),
                mock.patch("hermes_bootstrap.envfiles.secrets.token_urlsafe", return_value="fixture-signing-secret"),
                mock.patch.dict(os.environ, {API_URL_ENV: github.url}),
            ):
                yield

    def _apply(self, token: str = FIXTURE_TOKEN) -> dict[str, object]:
        with self._patched_runtime():
            return app.apply(PRODUCTION_MANIFEST, self._payload(token))

    def _validate(self) -> dict[str, object]:
        with self._patched_runtime():
            return app.validate(PRODUCTION_MANIFEST)

    def _initial_apply(self) -> None:
        self.assertEqual(self._apply()["status"], "applied")

    def _assert_no_temporary_resources(self) -> None:
        if not hasattr(self, "data_root"):
            return
        names = [path.name for path in self.data_root.glob(".hermes-bootstrap-*")]
        names.extend(path.name for path in self.data_root.glob(".hermes-repository-*"))
        journals = self.data_root / ".bootstrap" / "transactions"
        if journals.exists():
            names.extend(path.name for path in journals.iterdir() if path.name != ".lock")
        self.assertEqual(names, [])

    @staticmethod
    def _mode(path: Path) -> int:
        return stat.S_IMODE(path.lstat().st_mode)

    def test_initial_install_stages_distributions_and_preserves_runtime(self) -> None:
        self._initial_apply()

        self.assertEqual((self.data_root / "config.yaml").read_text(encoding="utf-8"), "root: initial\n")
        for profile in PROFILE_NAMES:
            target = self.data_root / "profiles" / profile
            self.assertEqual((target / "config.yaml").read_text(encoding="utf-8"), f"profile: {profile}-initial\n")
            self.assertEqual((target / "memories" / "runtime.txt").read_text(encoding="utf-8"), f"{profile} memory\n")
            self.assertEqual(self._mode(target / ".env"), 0o600)
        self.assertEqual((self.data_root / "memories" / "root.txt").read_text(encoding="utf-8"), "root memory\n")
        self.assertEqual(self._mode(self.data_root / ".env"), 0o600)
        lifelog = self.data_root / "shared" / "lifelog"
        legacy = self.data_root / "core" / "lifelog"
        self.assertTrue((lifelog / ".git").is_dir())
        self.assertTrue(legacy.is_symlink())
        self.assertEqual(os.readlink(legacy), "../shared/lifelog")
        self.assertEqual(self._validate()["status"], "valid")

    def test_identical_second_apply_keeps_owned_inodes_and_runtime_untouched(self) -> None:
        self._initial_apply()
        owned = self.data_root / "config.yaml"
        root_sentinel = self.data_root / "memories" / "root.txt"
        profile_sentinel = self.data_root / "profiles" / "rick" / "memories" / "runtime.txt"
        before = {
            "owned": (owned.stat().st_ino, owned.read_bytes()),
            "root": (root_sentinel.read_bytes(), self._mode(root_sentinel)),
            "profile": (profile_sentinel.read_bytes(), self._mode(profile_sentinel)),
            "commits": run_git("rev-list", "--count", "HEAD", cwd=self.data_root / "shared" / "lifelog"),
        }

        self._initial_apply()

        self.assertEqual((owned.stat().st_ino, owned.read_bytes()), before["owned"])
        self.assertEqual((root_sentinel.read_bytes(), self._mode(root_sentinel)), before["root"])
        self.assertEqual((profile_sentinel.read_bytes(), self._mode(profile_sentinel)), before["profile"])
        self.assertEqual(run_git("rev-list", "--count", "HEAD", cwd=self.data_root / "shared" / "lifelog"), before["commits"])

    def test_profile_update_replaces_only_owned_profile_content(self) -> None:
        self._initial_apply()
        self._commit("rick", {"config.yaml": "profile: rick-updated\n"}, "update rick")

        self._initial_apply()

        target = self.data_root / "profiles" / "rick"
        self.assertEqual((target / "config.yaml").read_text(encoding="utf-8"), "profile: rick-updated\n")
        self.assertEqual((target / "memories" / "runtime.txt").read_text(encoding="utf-8"), "rick memory\n")
        self.assertEqual((target / "sessions" / "runtime.txt").read_text(encoding="utf-8"), "rick session\n")

    def test_root_update_removes_retired_owned_path_without_runtime_loss(self) -> None:
        self._initial_apply()
        self._commit(
            "root",
            {"root-distribution.yaml": self._root_manifest(["config.yaml"]), "retired.md": None},
            "retire root path",
        )

        self._initial_apply()

        self.assertFalse((self.data_root / "retired.md").exists())
        self.assertEqual((self.data_root / "cron" / "state" / "runtime.txt").read_text(encoding="utf-8"), "root cron state\n")

    def test_legacy_lifelog_checkout_migrates_to_canonical_relative_link(self) -> None:
        legacy = self.data_root / "core" / "lifelog"
        legacy.parent.mkdir(parents=True)
        run_git("clone", str(self.source_remotes["lifelog"]), str(legacy))
        run_git("config", "user.name", "Fixture", cwd=legacy)
        run_git("config", "user.email", "fixture@example.test", cwd=legacy)

        self._initial_apply()

        canonical = self.data_root / "shared" / "lifelog"
        self.assertTrue((canonical / ".git").is_dir())
        self.assertTrue(legacy.is_symlink())
        self.assertEqual(os.readlink(legacy), "../shared/lifelog")

    def test_lifelog_pushes_allowed_changes_and_rejects_forbidden_ones(self) -> None:
        self._initial_apply()
        checkout = self.data_root / "shared" / "lifelog"
        remote_before = run_git("--git-dir", str(self.source_remotes["lifelog"]), "rev-parse", "main")
        (checkout / "entry.md").write_text("allowed\n", encoding="utf-8")

        self._initial_apply()

        remote_after = run_git("--git-dir", str(self.source_remotes["lifelog"]), "rev-parse", "main")
        self.assertNotEqual(remote_after, remote_before)
        self.assertEqual(run_git("rev-parse", "HEAD", cwd=checkout), remote_after)
        (checkout / ".env").write_text("forbidden\n", encoding="utf-8")
        with self.assertRaises(RepositoryError):
            self._apply()
        self.assertEqual(run_git("--git-dir", str(self.source_remotes["lifelog"]), "rev-parse", "main"), remote_after)
        (checkout / ".env").unlink()

    def test_invalid_token_fails_before_scratch_transaction_or_target_mutation(self) -> None:
        before = {
            path.relative_to(self.data_root): path.read_bytes()
            for path in self.data_root.rglob("*")
            if path.is_file() and not path.is_relative_to(self.data_root / ".bootstrap")
        }

        with self.assertRaises(CredentialError):
            self._apply("invalid-fixture-token")

        after = {
            path.relative_to(self.data_root): path.read_bytes()
            for path in self.data_root.rglob("*")
            if path.is_file() and not path.is_relative_to(self.data_root / ".bootstrap")
        }
        self.assertEqual(after, before)
        journal = self.data_root / ".bootstrap" / "transactions"
        self.assertFalse(journal.exists() and any(path.name != ".lock" for path in journal.iterdir()))

    def test_distribution_failure_rolls_back_local_state_after_remote_sync(self) -> None:
        self._initial_apply()
        before = self._snapshot_runtime()
        checkout = self.data_root / "shared" / "lifelog"
        (checkout / "remote-survives.md").write_text("remote change\n", encoding="utf-8")
        remote_before = run_git("--git-dir", str(self.source_remotes["lifelog"]), "rev-parse", "main")

        with self._patched_runtime(), mock.patch.object(
            app,
            "_failpoint",
            side_effect=lambda name: (_ for _ in ()).throw(ApplyError("fixture failure")) if name == "env-merge:rick" else None,
        ):
            with self.assertRaises(ApplyError):
                app.apply(PRODUCTION_MANIFEST, self._payload())

        self.assertEqual(self._snapshot_runtime(), before)
        remote_after = run_git("--git-dir", str(self.source_remotes["lifelog"]), "rev-parse", "main")
        self.assertNotEqual(remote_after, remote_before)
        self.assertTrue((checkout / "remote-survives.md").exists())

    def test_env_merge_preserves_unowned_content_and_canonicalizes_managed_keys(self) -> None:
        self._initial_apply()

        root_env = (self.data_root / ".env").read_text(encoding="utf-8")
        self.assertIn("# root comment", root_env)
        self.assertIn("CUSTOM_ROOT=keep", root_env)
        self.assertNotIn("HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=", root_env)
        for key in (
            "GH_TOKEN",
            "GITHUB_TOKEN",
            "GITHUB_PERSONAL_ACCESS_TOKEN",
            "HERMES_DASHBOARD_BASIC_AUTH_USERNAME",
            "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH",
            "HERMES_DASHBOARD_BASIC_AUTH_SECRET",
            "SLACK_BOT_TOKEN",
            "SLACK_APP_TOKEN",
            "SLACK_ALLOWED_USERS",
        ):
            self.assertEqual(sum(line.startswith(f"{key}=") for line in root_env.splitlines()), 1)

    def test_next_apply_recovers_crashed_durable_transaction_before_reading_payload(self) -> None:
        self._initial_apply()
        target = self.data_root / "config.yaml"
        expected = target.read_text(encoding="utf-8")
        script = (
            "from pathlib import Path; import os; "
            "from hermes_bootstrap.transaction import Transaction; "
            f"path=Path({str(target)!r}); tx=Transaction.begin(path.parents[0]); tx.snapshot(path); "
            "path.write_text('crashed mutation\\n', encoding='utf-8'); tx._release_lock(); os._exit(0)"
        )
        environment = {**os.environ, "PYTHONPATH": str(BOOTSTRAP_ROOT)}
        subprocess.run((sys.executable, "-c", script), check=True, env=environment, stdin=subprocess.DEVNULL)
        self.assertNotEqual(target.read_text(encoding="utf-8"), expected)
        original_reader = app.read_secret_payload

        def reader(stream: io.StringIO, manifest: BootstrapManifest) -> object:
            self.assertEqual(target.read_text(encoding="utf-8"), expected)
            return original_reader(stream, manifest)

        with self._patched_runtime(), mock.patch.object(app, "read_secret_payload", side_effect=reader):
            result = app.apply(PRODUCTION_MANIFEST, self._payload())
        self.assertEqual(result["status"], "applied")
        self.assertEqual(target.read_text(encoding="utf-8"), expected)

    def _snapshot_runtime(self) -> dict[str, tuple[str, bytes | str, int]]:
        snapshot: dict[str, tuple[str, bytes | str, int]] = {}
        for path in sorted(self.data_root.rglob("*")):
            relative = path.relative_to(self.data_root).as_posix()
            if relative.startswith(".bootstrap/transactions/"):
                continue
            metadata = path.lstat()
            if path.is_symlink():
                snapshot[relative] = ("symlink", os.readlink(path), self._mode(path))
            elif path.is_file():
                snapshot[relative] = ("file", path.read_bytes(), self._mode(path))
            elif path.is_dir():
                snapshot[relative] = ("dir", b"", self._mode(path))
        return snapshot


if __name__ == "__main__":
    unittest.main()
