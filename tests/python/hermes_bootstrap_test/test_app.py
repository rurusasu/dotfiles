from __future__ import annotations

import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


BOOTSTRAP_ROOT = Path(__file__).resolve().parents[3] / "scripts" / "python"
sys.path.insert(0, str(BOOTSTRAP_ROOT))

from hermes_bootstrap.errors import RepositoryError
from hermes_bootstrap.models import BootstrapManifest, DistributionSource, SharedRepository
from hermes_bootstrap.profile_sync import ProfileSyncReport
from hermes_bootstrap.repositories import RemoteSyncResult


def manifest(root: Path) -> BootstrapManifest:
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
            for name in ("rick",)
        ),
        shared_repositories=(
            SharedRepository(
                "lifelog",
                "https://github.com/example/lifelog.git",
                "main",
                root / "shared" / "lifelog",
            ),
        ),
    )


class AppTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(os.path.realpath(self.temp.name)) / "data"
        self.root.mkdir()
        self.manifest = manifest(self.root)

    def write_installed_profile(self) -> Path:
        target = self.root / "profiles" / "rick"
        target.mkdir(parents=True, exist_ok=True)
        (target / "distribution.yaml").write_text(
            json.dumps(
                {
                    "name": "rick",
                    "version": "0.1.0",
                    "hermes_requires": ">=0.18.2",
                    "distribution_owned": ["config.yaml"],
                    "source": self.manifest.profiles[0].source,
                }
            ),
            encoding="utf-8",
        )
        return target

    def write_root_state(self) -> None:
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

    def write_repository_metadata(self) -> None:
        repo = self.manifest.shared_repositories[0]
        repo.target.mkdir(parents=True)
        environment = {
            key: value for key, value in os.environ.items()
            if not key.upper().startswith("GIT_")
        }
        environment.update({"GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull})
        for arguments in (
            ("init", "--quiet"),
            ("-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "--quiet", "--allow-empty", "-m", "initial"),
            ("remote", "add", "origin", repo.source),
        ):
            subprocess.run(("git", *arguments), cwd=repo.target, env=environment, check=True, capture_output=True)

    def write_valid_layout(self) -> None:
        self.write_root_state()
        target = self.write_installed_profile()
        calendar_config = (
            "memory:\n"
            "  provider: builtin\n"
            "plugins:\n"
            "  enabled:\n"
            "    - hermes-lcm\n"
            "context:\n"
            "  engine: lcm\n"
            "mcp_servers:\n"
            "  chrome:\n"
            "    url: http://127.0.0.1:8765/mcp\n"
            "    connect_timeout: 120\n"
            "  calendar:\n"
            "    command: npx\n"
            "    args:\n"
            "      - --yes\n"
            "      - --package\n"
            '      - "@cocal/google-calendar-mcp@2.6.2"\n'
            "      - google-calendar-mcp\n"
            "    connect_timeout: 300\n"
            "    env:\n"
            f"      GOOGLE_OAUTH_CREDENTIALS: {self.root}/google-calendar-mcp/gcp-oauth.keys.json\n"
            f"      GOOGLE_CALENDAR_MCP_TOKEN_PATH: {self.root}/google-calendar-mcp/tokens.json\n"
            "  gmail:\n"
            "    command: npx\n"
            "    args:\n"
            "      - --yes\n"
            "      - --package\n"
            '      - "@artymclabin/gmail-mcp@1.2.3"\n'
            "      - gmail-mcp\n"
            "    connect_timeout: 300\n"
            "    env:\n"
            f"      GMAIL_OAUTH_PATH: {self.root}/google-gmail-mcp/gcp-oauth.keys.json\n"
            f"      GMAIL_CREDENTIALS_PATH: {self.root}/google-gmail-mcp/credentials.json\n"
            "    tools:\n"
            "      include:\n"
            "        - search_emails\n"
            "        - read_email\n"
            "        - get_thread\n"
            "        - list_inbox_threads\n"
            "        - get_inbox_with_threads\n"
            "        - list_email_labels\n"
            "        - draft_email\n"
            "      resources: false\n"
            "      prompts: false\n"
            "  xapi:\n"
            "    url: http://127.0.0.1:8766/mcp\n"
            "    connect_timeout: 300\n"
        )
        for config in (self.root / "config.yaml", target / "config.yaml"):
            config.write_text(calendar_config, encoding="utf-8")
            config.chmod(0o600)
        credentials = self.root / "google-calendar-mcp"
        credentials.mkdir(mode=0o700)
        oauth = credentials / "gcp-oauth.keys.json"
        tokens = credentials / "tokens.json"
        oauth.write_text(
            '{"installed":{"client_id":"id","client_secret":"secret"}}',
            encoding="utf-8",
        )
        tokens.write_text(
            '{"accounts":{"shared":{"refresh_token":"refresh"}}}',
            encoding="utf-8",
        )
        oauth.chmod(0o600)
        tokens.chmod(0o600)
        gmail_credentials = self.root / "google-gmail-mcp"
        gmail_credentials.mkdir(mode=0o700)
        gmail_oauth = gmail_credentials / "gcp-oauth.keys.json"
        gmail_tokens = gmail_credentials / "credentials.json"
        gmail_oauth.write_text(
            '{"installed":{"client_id":"id","client_secret":"secret"}}',
            encoding="utf-8",
        )
        gmail_tokens.write_text(
            '{"tokens":{"refresh_token":"refresh"},'
            '"scopes":["gmail.readonly","gmail.compose"]}',
            encoding="utf-8",
        )
        gmail_oauth.chmod(0o600)
        gmail_tokens.chmod(0o600)
        self.write_repository_metadata()

    def test_engine_lock_contention_blocks_mutating_work_before_side_effects(self) -> None:
        from hermes_bootstrap import app

        events: list[str] = []

        def unavailable(_root: Path) -> None:
            events.append("lock-acquire")
            raise RepositoryError("bootstrap engine lock is unavailable")

        with (
            mock.patch.object(app, "load_manifest", return_value=self.manifest),
            mock.patch.object(app.EngineLock, "acquire", side_effect=unavailable),
            mock.patch.object(app, "_private_scratch", side_effect=lambda *_: events.append("scratch")),
            mock.patch.object(app, "stage_distribution", side_effect=lambda *_: events.append("git")),
            mock.patch.object(app, "synchronize_remote", side_effect=lambda *_: events.append("git")),
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

    def test_sync_commands_use_process_aliases_then_onepassword_without_reading_env_files(self) -> None:
        from hermes_bootstrap import app

        active = self.root / "profiles" / "rick"
        active.mkdir(parents=True)
        legacy = {self.root / ".env": b"\xffroot-secret", active / ".env": b"\xffprofile-secret"}
        for path, content in legacy.items():
            path.write_bytes(content)
        cases = (
            ({"GH_TOKEN": "process-token", "GITHUB_TOKEN": "github-token", "GITHUB_PERSONAL_ACCESS_TOKEN": "personal-token"}, "process-token", False),
            ({"GH_TOKEN": "", "GITHUB_TOKEN": "github-token", "GITHUB_PERSONAL_ACCESS_TOKEN": "personal-token"}, "github-token", False),
            ({"GITHUB_PERSONAL_ACCESS_TOKEN": "personal-token"}, "personal-token", False),
            ({"HERMES_HOME": "/unrelated/home"}, "onepassword-token", True),
        )
        for command in ("repository", "profiles"):
            for environ, expected_token, use_onepassword in cases:
                report = ProfileSyncReport(dry_run=True, profiles=(), exit_code=0)
                with (
                    self.subTest(command=command, expected_token=expected_token),
                    mock.patch.object(app, "load_manifest", return_value=self.manifest),
                    mock.patch("hermes_bootstrap.onepassword.read_github_token", return_value="onepassword-token") as read_token,
                    mock.patch.object(app, "synchronize_named_repository", return_value=RemoteSyncResult("lifelog", "a" * 40, False, self.root / "shared" / "lifelog")) as repository_sync,
                    mock.patch.object(app.profile_sync, "synchronize_profiles", return_value=report) as profile_sync,
                ):
                    if command == "repository":
                        result = app.sync_repository(Path("manifest.yaml"), "lifelog", environ)
                        self.assertEqual(result["name"], "lifelog")
                        auth = repository_sync.call_args.args[2]
                    else:
                        result = app.sync_profiles(Path("manifest.yaml"), dry_run=True, environ=environ)
                        self.assertIs(result, report)
                        auth = profile_sync.call_args.args[1]
                        self.assertEqual(profile_sync.call_args.kwargs, {"dry_run": True})
                    self.assertEqual(auth.token, expected_token)
                    self.assertNotIn(expected_token, repr(result))
                    if use_onepassword:
                        read_token.assert_called_once_with(self.manifest, environ)
                    else:
                        read_token.assert_not_called()
        for path, content in legacy.items():
            self.assertEqual(path.read_bytes(), content)

    def test_installed_layout_validation_preserves_unmanaged_profile_entries(self) -> None:
        from hermes_bootstrap import app

        self.write_valid_layout()
        profiles = self.root / "profiles"
        extra_profile = profiles / "local"
        extra_profile.mkdir()
        (extra_profile / "notes.txt").write_text("keep me\n", encoding="utf-8")
        metadata = profiles / ".DS_Store"
        metadata.write_bytes(b"finder metadata")
        legacy = self.root / ".env"
        legacy.write_bytes(b"\xfflegacy-secret-marker")

        result = app._validate_installed_layout(
            self.manifest
        )

        self.assertEqual(result, {"profiles": ["rick"], "repositories": ["lifelog"]})
        self.assertEqual((extra_profile / "notes.txt").read_text(encoding="utf-8"), "keep me\n")
        self.assertEqual(metadata.read_bytes(), b"finder metadata")
        self.assertEqual(legacy.read_bytes(), b"\xfflegacy-secret-marker")
