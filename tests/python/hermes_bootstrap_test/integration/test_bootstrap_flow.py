"""Repeatable end-to-end coverage for the Hermes bootstrap runtime."""

from __future__ import annotations

import io
import json
import os
import signal
import stat
import subprocess
import sys
import tempfile
import unittest
from contextlib import contextmanager, redirect_stderr, redirect_stdout
from dataclasses import dataclass, replace
from pathlib import Path
from typing import Iterator
from unittest import mock

import yaml

from hermes_cli import profile_distribution


REPOSITORY_ROOT = Path(__file__).resolve().parents[4]
BOOTSTRAP_ROOT = REPOSITORY_ROOT / "scripts" / "python"
sys.path.insert(0, str(BOOTSTRAP_ROOT))

from hermes_bootstrap import app, cli, google_calendar
from hermes_bootstrap.errors import (
    ApplyError,
    RepositoryError,
    ValidationError,
)
from hermes_bootstrap.git import StagedSource, stage_distribution
import hermes_bootstrap.git as git_module
from hermes_bootstrap.manifest import load_manifest
from hermes_bootstrap.models import BootstrapManifest, DistributionSource
from hermes_bootstrap.onepassword import build_onepassword_config
from hermes_bootstrap.payload import SCHEMA_VERSION


FIXTURE_TOKEN = "fixture-token-only"
HOST_SECRET_ENV = "HERMES_BOOTSTRAP_TEST_HOST_SECRET"
HOST_SECRET_VALUE = "planted-host-secret-marker"
PRODUCTION_MANIFEST = REPOSITORY_ROOT / "nix/modules/ai_agents/hermes/manifest.yaml"
PRODUCTION_PROFILES = load_manifest(PRODUCTION_MANIFEST).profiles
PROFILE_NAMES = tuple(source.name for source in PRODUCTION_PROFILES)
PROFILE_IDENTITIES = {
    source.name: {
        "version": "0.1.0",
        "hermes_requires": ">=0.18.2",
        "distribution_owned": ("SOUL.md", "config.yaml"),
    }
    for source in PRODUCTION_PROFILES
}
PROFILE_USER_DIRECTORIES = (
    "memories",
    "sessions",
    "skills",
    "skins",
    "logs",
    "plans",
    "workspace",
    "cron",
    "home",
)
GMAIL_CONFIGURATION = {
    "command": "npx",
    "args": ["--yes", "--package", "@artymclabin/gmail-mcp@1.2.3", "gmail-mcp"],
    "connect_timeout": 300,
    "env": {
        "GMAIL_OAUTH_PATH": "/opt/data/google-gmail-mcp/gcp-oauth.keys.json",
        "GMAIL_CREDENTIALS_PATH": "/opt/data/google-gmail-mcp/credentials.json",
    },
    "tools": {
        "include": [
            "search_emails",
            "read_email",
            "get_thread",
            "list_inbox_threads",
            "get_inbox_with_threads",
            "list_email_labels",
            "draft_email",
        ],
        "resources": False,
        "prompts": False,
    },
}
_MANAGED_GIT_EXECUTABLE = os.environ.get("DOTFILES_HERMES_GIT_EXECUTABLE")
SAFE_PATH = os.pathsep.join(
    ([str(Path(_MANAGED_GIT_EXECUTABLE).parent)] if _MANAGED_GIT_EXECUTABLE else [])
    + ["/usr/bin", "/bin"]
)
PROCESS_TIMEOUT_SECONDS = 15.0
PROCESS_STOP_TIMEOUT_SECONDS = 2.0
_REAL_POPEN = subprocess.Popen
_CHILD_PROCESSES: list[subprocess.Popen[object]] = []


def source_config(key: str, value: str, data_root: Path | None = None) -> str:
    root = data_root if data_root is not None else Path("/opt/data")
    return (
        f"{key}: {value}\n"
        "agent:\n"
        "  disabled_toolsets:\n"
        "    - browser\n"
        "mcp_servers:\n"
        "  chrome:\n"
        "    url: http://127.0.0.1:8765/mcp\n"
        "    connect_timeout: 120\n"
        "  xapi:\n"
        "    url: http://127.0.0.1:8766/mcp\n"
        "    connect_timeout: 300\n"
        "  calendar:\n"
        "    command: npx\n"
        '    args: [--yes, --package, "@cocal/google-calendar-mcp@2.6.2", google-calendar-mcp]\n'
        "    connect_timeout: 300\n"
        "    env:\n"
        f"      GOOGLE_OAUTH_CREDENTIALS: {root / 'google-calendar-mcp/gcp-oauth.keys.json'}\n"
        f"      GOOGLE_CALENDAR_MCP_TOKEN_PATH: {root / 'google-calendar-mcp/tokens.json'}\n"
    )


def managed_source_config(
    manifest: BootstrapManifest, profile: str, key: str, value: str
) -> str:
    config = yaml.safe_load(source_config(key, value, manifest.data_root))
    assert isinstance(config, dict)
    mcp_servers = config["mcp_servers"]
    assert isinstance(mcp_servers, dict)
    gmail_configuration = json.loads(json.dumps(GMAIL_CONFIGURATION))
    gmail_configuration["env"] = {
        "GMAIL_OAUTH_PATH": str(
            manifest.data_root / "google-gmail-mcp/gcp-oauth.keys.json"
        ),
        "GMAIL_CREDENTIALS_PATH": str(
            manifest.data_root / "google-gmail-mcp/credentials.json"
        ),
    }
    mcp_servers["gmail"] = gmail_configuration
    config["context"] = {"engine": "lcm"}
    config["plugins"] = {"enabled": ["hermes-lcm"]}
    managed = build_onepassword_config(manifest, profile)
    additions = {"secrets": {"onepassword": managed}}
    environment = managed["env"]
    if isinstance(environment, dict) and "DISCORD_BOT_TOKEN" in environment:
        additions["platforms"] = {"discord": {"allow_bots": "mentions"}}
    return (
        yaml.safe_dump(config, sort_keys=False)
        + yaml.safe_dump(additions, sort_keys=False)
    )


@dataclass(frozen=True)
class TreeEntry:
    kind: str
    mode: int
    payload: bytes | str | None


def _minimal_environment(home: Path, **extra: str) -> dict[str, str]:
    return {
        "PATH": SAFE_PATH,
        "HOME": str(home),
        "LANG": "C",
        "LC_ALL": "C",
        **extra,
    }


def _stop_process(process: subprocess.Popen[object]) -> None:
    if process.poll() is not None:
        return
    try:
        if os.name == "posix":
            os.killpg(process.pid, signal.SIGKILL)
        else:
            process.kill()
    except OSError:
        try:
            process.kill()
        except OSError:
            pass
    try:
        process.wait(timeout=PROCESS_STOP_TIMEOUT_SECONDS)
    except (OSError, subprocess.TimeoutExpired):
        pass


def _run_bounded(
    arguments: tuple[str, ...],
    *,
    cwd: Path | None = None,
    environment: dict[str, str],
    timeout: float = PROCESS_TIMEOUT_SECONDS,
) -> subprocess.CompletedProcess[str]:
    process = _REAL_POPEN(
        arguments,
        cwd=cwd,
        env=environment,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        close_fds=True,
        start_new_session=True,
    )
    _CHILD_PROCESSES.append(process)
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        _stop_process(process)
        raise AssertionError("fixture child process exceeded its timeout") from None
    finally:
        _stop_process(process)
    return subprocess.CompletedProcess(arguments, process.returncode, stdout, stderr)


def run_git(*arguments: str, cwd: Path | None = None) -> str:
    environment = _minimal_environment(
        Path("/nonexistent"),
        GIT_CONFIG_GLOBAL=os.devnull,
        GIT_CONFIG_NOSYSTEM="1",
        GIT_TERMINAL_PROMPT="0",
    )
    if HOST_SECRET_ENV in os.environ:
        assert os.environ[HOST_SECRET_ENV] == HOST_SECRET_VALUE
    assert HOST_SECRET_ENV not in environment
    completed = _run_bounded(
        ("git", *arguments),
        cwd=cwd,
        environment=environment,
    )
    visible_output = completed.stdout + completed.stderr
    assert HOST_SECRET_ENV not in visible_output
    assert HOST_SECRET_VALUE not in visible_output
    if completed.returncode != 0:
        raise subprocess.CalledProcessError(
            completed.returncode,
            completed.args,
            output=completed.stdout,
            stderr=completed.stderr,
        )
    return completed.stdout.strip()


class BootstrapFlowTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.host_secret = mock.patch.dict(
            os.environ, {HOST_SECRET_ENV: HOST_SECRET_VALUE}
        )
        self.host_secret.start()
        self.addCleanup(self.host_secret.stop)
        self.fixture_root = Path(self.temporary.name)
        self.child_process_offset = len(_CHILD_PROCESSES)
        self.child_arguments: list[tuple[str, ...]] = []
        self.profile_stage_refs: list[tuple[str, str, str, str, str]] = []
        self.child_home = self.fixture_root / "child-home"
        self.profile_tmpdir = self.fixture_root / "tmp"
        self.child_home.mkdir()
        self.profile_tmpdir.mkdir()
        self.profile_tmpdir_before = self._snapshot_tree(
            self.profile_tmpdir, include_root=False
        )
        self.data_root = self.fixture_root / "data"
        self.data_root.mkdir()
        self.remotes = self.fixture_root / "remotes"
        self.seed_root = self.fixture_root / "seeds"
        self.remotes.mkdir()
        self.seed_root.mkdir()
        self.seeds: dict[str, Path] = {}
        self.source_remotes: dict[str, Path] = {}
        self._create_sources()
        self.manifest = self._local_manifest()
        self._write_runtime_sentinels()
        self._ensure_profile_locks()

    def tearDown(self) -> None:
        try:
            self._assert_no_temporary_resources()
        finally:
            self._assert_no_live_children()

    def _create_sources(self) -> None:
        self._create_distribution(
            "root",
            {
                "root-distribution.yaml": self._root_manifest(["config.yaml", "retired.md"]),
                "config.yaml": source_config("root", "initial", self.data_root),
                "retired.md": "retire me\n",
            },
        )
        for profile in PROFILE_NAMES:
            self._create_distribution(
                profile,
                {
                    ".gitignore": self._profile_gitignore(),
                    "distribution.yaml": self._profile_manifest(profile),
                    "config.yaml": source_config(
                        "profile", f"{profile}-initial", self.data_root
                    ),
                    "SOUL.md": f"{profile} initial\n",
                },
            )
        self._create_distribution("lifelog", {"README.md": "initial lifelog\n"})

    def _create_distribution(self, name: str, files: dict[str, str]) -> None:
        remote = self.remotes / f"{name}.git"
        seed = self.seed_root / name
        run_git("init", "--bare", str(remote))
        run_git("init", "--initial-branch=main", str(seed))
        run_git("config", "user.name", "Fixture", cwd=seed)
        run_git("config", "user.email", "fixture@example.test", cwd=seed)
        self._write_files(seed, files)
        run_git("add", "-A", cwd=seed)
        run_git("commit", "-m", "initial fixture", cwd=seed)
        run_git("remote", "add", "origin", str(remote), cwd=seed)
        run_git("push", "origin", "main", cwd=seed)
        self.seeds[name] = seed
        self.source_remotes[name] = remote

    def _local_manifest(self) -> BootstrapManifest:
        parsed = load_manifest(PRODUCTION_MANIFEST)
        root = replace(
            parsed.root_distribution,
            target=self.data_root,
            source_commit=run_git("--git-dir", str(self.source_remotes["root"]), "rev-parse", "main"),
        )
        profiles = tuple(
            replace(
                source,
                target=self.data_root / "profiles" / source.name,
                source_commit=run_git(
                    "--git-dir",
                    str(self.source_remotes[source.name]),
                    "rev-parse",
                    "main",
                ),
            )
            for source in parsed.profiles
        )
        repositories = tuple(
            replace(
                repository,
                target=self.data_root / "shared" / repository.name,
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
            },
        )
        for profile in PROFILE_NAMES:
            target = self.data_root / "profiles" / profile
            self._write_files(
                target,
                {
                    "distribution.yaml": self._runtime_profile_manifest(profile),
                    "config.yaml": source_config(
                        "profile", f"{profile}-initial", self.data_root
                    ),
                    "SOUL.md": f"{profile} initial\n",
                    "memories/runtime.txt": f"{profile} memory\n",
                    "sessions/runtime.txt": f"{profile} session\n",
                },
            )
            for directory in PROFILE_USER_DIRECTORIES:
                (target / directory).mkdir(exist_ok=True)

    @staticmethod
    def _root_manifest(owned: list[str], version: str = "0.1.0") -> str:
        return "\n".join(
            [
                "schema_version: 1",
                "name: default",
                f"version: {version}",
                "hermes_requires: '>=0.18.2'",
                "distribution_owned:",
                *(f"  - {path}" for path in owned),
                "",
            ]
        )

    @staticmethod
    def _profile_manifest(
        name: str,
        version: str = "0.1.0",
        *,
        source: str | None = None,
    ) -> str:
        return "\n".join(
            [
                f"name: {name}",
                *([f"source: {source}"] if source is not None else []),
                f"version: {version}",
                "hermes_requires: '>=0.18.2'",
                "distribution_owned:",
                "- SOUL.md",
                "- config.yaml",
                "",
            ]
        )

    def _runtime_profile_manifest(
        self, name: str, version: str = "0.1.0"
    ) -> str:
        source = next(
            profile.source for profile in self.manifest.profiles
            if profile.name == name
        )
        return self._profile_manifest(name, version, source=source)

    @staticmethod
    def _profile_gitignore() -> str:
        return "\n".join(
            [
                "/*",
                "!/.gitignore",
                "!/distribution.yaml",
                "!/SOUL.md",
                "!/config.yaml",
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
        commit = run_git("rev-parse", "HEAD", cwd=seed)
        if name == "root":
            self.manifest = replace(
                self.manifest,
                root_distribution=replace(
                    self.manifest.root_distribution,
                    source_commit=commit,
                ),
            )
        else:
            self.manifest = replace(
                self.manifest,
                profiles=tuple(
                    replace(profile, source_commit=commit)
                    if profile.name == name
                    else profile
                    for profile in self.manifest.profiles
                ),
            )
        return commit

    def _payload(self, token: str = FIXTURE_TOKEN) -> io.StringIO:
        records: list[dict[str, object]] = [{"type": "header", "schema_version": SCHEMA_VERSION}]
        values = {
            "github": {"credential": token},
            "google_calendar": {
                "oauth_credentials_json": json.dumps(
                    {
                        "installed": {
                            "client_id": "fixture-calendar-client",
                            "client_secret": "fixture-calendar-secret",
                        }
                    }
                ),
                "tokens_json": json.dumps(
                    {
                        "accounts": {
                            "shared": {
                                "refresh_token": "fixture-calendar-refresh"
                            }
                        }
                    }
                ),
            },
        }
        for item in self.manifest.onepassword_items:
            if item.key not in values:
                continue
            fields = [
                {"label": field.labels[0], "value": values[item.key][field.canonical_name]}
                for field in item.fields
            ]
            records.append({"type": "item", "key": item.key, "item": {"id": f"fixture-{item.key}", "fields": fields}})
        records.append({"type": "end"})
        return io.StringIO("".join(json.dumps(record, sort_keys=True) + "\n" for record in records))

    @contextmanager
    def _patched_runtime(self) -> Iterator[None]:
        def audited_popen(*args: object, **kwargs: object) -> subprocess.Popen[object]:
            environment = kwargs.get("env")
            self.assertIsInstance(environment, dict)
            assert isinstance(environment, dict)
            command = args[0] if args else kwargs.get("args")
            self.assertIsInstance(command, (list, tuple))
            assert isinstance(command, (list, tuple))
            child_arguments = tuple(str(argument) for argument in command)
            self.child_arguments.append(child_arguments)
            visible_arguments = repr(child_arguments)
            self._assert_no_protected_output(
                visible_arguments, "child process arguments"
            )
            self.assertFalse(
                HOST_SECRET_ENV in environment,
                "child environment contained a protected host key",
            )
            self.assertFalse(
                HOST_SECRET_VALUE in environment.values(),
                "child environment contained a protected host value",
            )
            expected_base = _minimal_environment(self.child_home)
            if (
                isinstance(command, (list, tuple))
                and command
                and command[0] == git_module._GIT_EXECUTABLE
            ):
                expected_base["PATH"] = os.defpath
            self.assertEqual(
                {key: environment.get(key) for key in expected_base},
                expected_base,
            )
            unexpected = {
                key
                for key in environment
                if key not in expected_base
                and not key.startswith("GIT_")
                and key != "HERMES_BOOTSTRAP_GITHUB_TOKEN"
            }
            self.assertEqual(unexpected, set())
            if child_arguments[0] == git_module._GIT_EXECUTABLE:
                environment = self._redirect_git_transport(environment)
                kwargs["env"] = environment
            process = _REAL_POPEN(*args, **kwargs)  # type: ignore[arg-type]
            _CHILD_PROCESSES.append(process)
            return process

        with mock.patch.dict(os.environ, _minimal_environment(self.child_home), clear=True):
            def audited_stage(
                source: DistributionSource, workdir: Path, auth: object
            ) -> StagedSource:
                fixture_name = "root" if source.name == "default" else source.name
                staged = stage_distribution(source, workdir, auth)  # type: ignore[arg-type]
                if fixture_name in PROFILE_NAMES:
                    self.profile_stage_refs.append(
                        (
                            fixture_name,
                            source.source,
                            source.ref,
                            staged.commit,
                            run_git(
                                "--git-dir",
                                str(self.source_remotes[fixture_name]),
                                "rev-parse",
                                "main",
                            ),
                        )
                    )
                return staged

            with (
                mock.patch.object(app, "load_manifest", return_value=self.manifest),
                mock.patch.object(
                    app, "stage_distribution", side_effect=audited_stage
                ),
                mock.patch.object(subprocess, "Popen", side_effect=audited_popen),
                mock.patch.object(tempfile, "tempdir", str(self.profile_tmpdir)),
            ):
                yield

    def _redirect_git_transport(
        self, environment: dict[str, str]
    ) -> dict[str, str]:
        redirected = dict(environment)
        transport_remotes = {
            self.manifest.root_distribution.source: self.source_remotes["root"],
            **{
                source.source: self.source_remotes[source.name]
                for source in self.manifest.profiles
            },
            **{
                repository.source: self.source_remotes[repository.name]
                for repository in self.manifest.shared_repositories
            },
        }
        first = int(redirected.get("GIT_CONFIG_COUNT", "0"))
        for offset, (source, remote) in enumerate(transport_remotes.items()):
            index = first + offset
            redirected[f"GIT_CONFIG_KEY_{index}"] = (
                f"url.{remote.as_posix()}.insteadOf"
            )
            redirected[f"GIT_CONFIG_VALUE_{index}"] = source
        redirected["GIT_CONFIG_COUNT"] = str(first + len(transport_remotes))
        return redirected

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
        leaks: set[str] = set()
        for root in (self.data_root, self.data_root / "shared"):
            if not root.exists():
                continue
            for path in root.rglob("*"):
                if path.name.startswith(
                    (
                        ".hermes-bootstrap-",
                        ".hermes-profile-snapshots-",
                        ".hermes-profile-sync-",
                        ".hermes-repository-",
                        "askpass-",
                        "stage-",
                    )
                ) or ".bootstrap-" in path.name:
                    leaks.add(path.relative_to(self.data_root).as_posix())
        self.assertFalse(bool(leaks), "temporary resource leak (details redacted)")
        scratch_snapshot = self._snapshot_tree(
            self.profile_tmpdir, include_root=False
        )
        self.assertTrue(
            scratch_snapshot == self.profile_tmpdir_before,
            "profile scratch cleanup mismatch (details redacted)",
        )

    def _assert_no_live_children(self) -> None:
        live: list[int] = []
        for process in _CHILD_PROCESSES[self.child_process_offset :]:
            if process.poll() is None:
                live.append(process.pid)
                _stop_process(process)
        del _CHILD_PROCESSES[self.child_process_offset :]
        self.assertEqual(live, [])
        for _attempt in range(4096):
            try:
                child, _status = os.waitpid(-1, os.WNOHANG)
            except ChildProcessError:
                return
            self.assertNotEqual(child, 0, "an untracked live child process remains")
        self.fail("too many exited child processes required reaping")

    @staticmethod
    def _mode(path: Path) -> int:
        return stat.S_IMODE(path.lstat().st_mode)

    def _assert_no_protected_output(self, output: str, context: str) -> None:
        self.assertFalse(
            any(
                protected_value in output
                for protected_value in (FIXTURE_TOKEN, HOST_SECRET_VALUE)
            ),
            f"{context} contained a protected value",
        )

    def test_initial_install_stages_distributions_and_preserves_runtime(self) -> None:
        profiles_before = {
            profile: {
                path: (entry.kind, entry.mode, entry.payload)
                for path, entry in self._snapshot_tree(
                    self.data_root / "profiles" / profile
                ).items()
                if path not in {".env", "config.yaml"}
            }
            for profile in PROFILE_NAMES
        }

        self._initial_apply()

        self.assertEqual(
            (self.data_root / "config.yaml").read_text(encoding="utf-8"),
            managed_source_config(self.manifest, "default", "root", "initial"),
        )
        for profile in PROFILE_NAMES:
            target = self.data_root / "profiles" / profile
            self.assertEqual(
                (target / "config.yaml").read_text(encoding="utf-8"),
                managed_source_config(
                    self.manifest, profile, "profile", f"{profile}-initial"
                ),
            )
            self.assertEqual(
                {
                    path: (entry.kind, entry.mode, entry.payload)
                    for path, entry in self._snapshot_tree(target).items()
                    if path not in {".env", "config.yaml"}
                },
                profiles_before[profile],
            )
            self.assertEqual((target / "memories" / "runtime.txt").read_text(encoding="utf-8"), f"{profile} memory\n")
            self.assertFalse((target / ".env").exists())
        self.assertEqual((self.data_root / "memories" / "root.txt").read_text(encoding="utf-8"), "root memory\n")
        self.assertFalse((self.data_root / ".env").exists())
        lifelog = self.data_root / "shared" / "lifelog"
        legacy = self.data_root / "core" / "lifelog"
        self.assertTrue((lifelog / ".git").is_dir())
        self.assertFalse(os.path.lexists(legacy))
        self.assertEqual(self._validate()["status"], "valid")

    def test_profile_targets_keep_canonical_source_token_and_manifest_identity(self) -> None:
        production_profiles = {
            source.name: source for source in load_manifest(PRODUCTION_MANIFEST).profiles
        }
        command_stdout = io.StringIO()
        command_stderr = io.StringIO()
        ambient_stdout = io.StringIO()
        ambient_stderr = io.StringIO()
        with (
            redirect_stdout(ambient_stdout),
            redirect_stderr(ambient_stderr),
            self._patched_runtime(),
        ):
            exit_code = cli.main(
                ["apply", "--manifest", str(PRODUCTION_MANIFEST)],
                stdin=self._payload(),
                stdout=command_stdout,
                stderr=command_stderr,
            )

        visible_output = "".join(
            stream.getvalue()
            for stream in (
                command_stdout,
                command_stderr,
                ambient_stdout,
                ambient_stderr,
            )
        )
        self._assert_no_protected_output(visible_output, "successful apply output")
        self.assertEqual(exit_code, 0)
        self.assertEqual(
            json.loads(command_stdout.getvalue()),
            {
                "profile_sync": {profile.name: "preserved" for profile in self.manifest.profiles},
                "profiles": [profile.name for profile in self.manifest.profiles],
                "repositories": [repo.name for repo in self.manifest.shared_repositories],
                "status": "applied",
            },
        )
        self.assertEqual(command_stderr.getvalue(), "")
        self.assertEqual(ambient_stdout.getvalue(), "")
        # The pinned hermes_cli emits deprecation warnings here; the leak scan
        # above still treats ambient stderr as protected output.

        # Existing profiles are local-authoritative during apply, so their
        # remotes must not be accessed until the explicit sync-profiles route.
        declared_sources = (
            self.manifest.root_distribution,
            *self.manifest.shared_repositories,
        )
        visible_arguments = {
            argument
            for command in self.child_arguments
            for argument in command
        }
        for source in declared_sources:
            self.assertIn(source.source, visible_arguments)
        for remote in self.source_remotes.values():
            self.assertNotIn(str(remote), visible_arguments)

        self.assertEqual(self.profile_stage_refs, [])

        for name, expected in PROFILE_IDENTITIES.items():
            with self.subTest(profile=name):
                target = self.data_root / "profiles" / name
                self.assertTrue(target.is_dir())
                self.assertFalse(target.is_symlink())
                self.assertTrue((target / "distribution.yaml").is_file())
                installed = profile_distribution.read_manifest(target)
                self.assertIsNotNone(installed)
                assert installed is not None
                self.assertEqual(
                    {
                        "name": installed.name,
                        "source": installed.source,
                        "version": installed.version,
                        "hermes_requires": installed.hermes_requires,
                        "distribution_owned": tuple(sorted(installed.distribution_owned)),
                    },
                    {
                        "name": name,
                        "source": production_profiles[name].source,
                        **expected,
                    },
                )
                installed_config = yaml.safe_load(
                    (target / "config.yaml").read_text(encoding="utf-8")
                )
                self.assertEqual(
                    installed_config["secrets"]["onepassword"],
                    build_onepassword_config(self.manifest, name),
                )

    def test_identical_second_apply_preserves_the_target_and_runtime_tree(self) -> None:
        self._initial_apply()
        before = self._snapshot_managed_tree()
        lifelog = self.data_root / "shared" / "lifelog"
        lifelog_head = run_git("rev-parse", "HEAD", cwd=lifelog)
        lifelog_commits = run_git("rev-list", "--count", "HEAD", cwd=lifelog)

        self._initial_apply()

        self.assertEqual(self._snapshot_managed_tree(), before)
        self.assertEqual(run_git("rev-parse", "HEAD", cwd=lifelog), lifelog_head)
        self.assertEqual(run_git("rev-list", "--count", "HEAD", cwd=lifelog), lifelog_commits)

    def test_local_profile_update_publishes_and_preserves_runtime_content(self) -> None:
        self._initial_apply()
        target = self.data_root / "profiles" / "rick"
        runtime = target / "memories" / "runtime.txt"
        runtime_before = (runtime.read_bytes(), self._mode(runtime))
        remote_before = run_git(
            "--git-dir", str(self.source_remotes["rick"]), "rev-parse", "main"
        )
        self._write_files(
            target,
            {
                "distribution.yaml": self._runtime_profile_manifest(
                    "rick", "0.2.0"
                ),
                "config.yaml": source_config(
                    "profile", "rick-updated", self.data_root
                ),
            },
        )

        self._initial_apply()

        installed = profile_distribution.read_manifest(target)
        self.assertIsNotNone(installed)
        self.assertEqual(installed.version, "0.2.0")
        self.assertEqual(
            installed.source,
            next(source.source for source in self.manifest.profiles if source.name == "rick"),
        )
        self.assertEqual(
            (target / "config.yaml").read_text(encoding="utf-8"),
            managed_source_config(
                self.manifest, "rick", "profile", "rick-updated"
            ),
        )
        self.assertEqual(
            (runtime.read_bytes(), self._mode(runtime)),
            runtime_before,
        )
        self.assertEqual((target / "sessions" / "runtime.txt").read_text(encoding="utf-8"), "rick session\n")
        self.assertEqual(
            run_git(
                "--git-dir",
                str(self.source_remotes["rick"]),
                "rev-parse",
                "main",
            ),
            remote_before,
        )

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

    def test_initial_publication_survives_a_later_failure_and_retry_completes(self) -> None:
        canonical = self.data_root / "shared" / "lifelog"
        missing = self.manifest.profiles[-1]
        missing.target.rename(self.fixture_root / "saved-profile")
        user_data = self._snapshot_user_data()
        existing_profiles = {
            profile.name: self._snapshot_tree(profile.target)
            for profile in self.manifest.profiles
            if profile != missing
        }
        remote_heads = {
            name: run_git("--git-dir", str(remote), "rev-parse", "main")
            for name, remote in self.source_remotes.items()
        }

        with (
            self._patched_runtime(),
            mock.patch.object(
                app,
                "install_google_calendar_configurations",
                side_effect=ApplyError("fixture configuration failure"),
            ),
            self.assertRaisesRegex(ApplyError, "fixture configuration failure"),
        ):
            app.apply(PRODUCTION_MANIFEST, self._payload())

        self.assertTrue((canonical / ".git").is_dir())
        self.assertTrue((missing.target / "distribution.yaml").is_file())
        self.assertTrue((self.data_root / "config.yaml").is_file())
        current_user_data = self._snapshot_user_data()
        self.assertEqual({path: current_user_data.get(path) for path in user_data}, user_data)
        for profile in self.manifest.profiles:
            if profile != missing:
                self.assertEqual(self._snapshot_tree(profile.target), existing_profiles[profile.name])
        self.assertEqual(
            {
                name: run_git("--git-dir", str(remote), "rev-parse", "main")
                for name, remote in self.source_remotes.items()
            },
            remote_heads,
        )
        self._initial_apply()
        self.assertTrue((canonical / ".git").is_dir())
        self.assertTrue((missing.target / "distribution.yaml").is_file())
        current_user_data = self._snapshot_user_data()
        self.assertEqual({path: current_user_data.get(path) for path in user_data}, user_data)
        self.assertEqual(self._validate()["status"], "valid")

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

    def test_future_profile_chrome_validation_precedes_remote_and_local_mutation(
        self,
    ) -> None:
        future = "future"
        self._create_distribution(
            future,
            {
                "distribution.yaml": self._profile_manifest(future),
                "config.yaml": source_config(
                    "profile", "future-invalid", self.data_root
                ).replace(
                    "    connect_timeout: 120\n",
                    "    connect_timeout: 120.0\n",
                ),
                "SOUL.md": "future initial\n",
            },
        )
        future_source = DistributionSource(
            name=future,
            source="https://github.com/rurusasu/hermes-profile-future.git",
            ref="main",
            target=self.data_root / "profiles" / future,
            manifest_name="distribution.yaml",
        )
        future_discord_item = replace(
            next(
                item
                for item in self.manifest.onepassword_items
                if item.key == "discord_rick"
            ),
            key="discord_future",
            item="Hermes Discord future",
        )
        self.manifest = replace(
            self.manifest,
            profiles=(*self.manifest.profiles, future_source),
            onepassword_items=(
                *self.manifest.onepassword_items,
                future_discord_item,
            ),
        )
        before = self._snapshot_managed_tree()

        with (
            self._patched_runtime(),
            mock.patch.object(
                app,
                "synchronize_remote",
                wraps=app.synchronize_remote,
            ) as synchronize_remote,
            mock.patch.object(
                app,
                "apply_root_distribution",
                wraps=app.apply_root_distribution,
            ) as apply_root,
        ):
            with self.assertRaises(ValidationError):
                app.apply(PRODUCTION_MANIFEST, self._payload())

        synchronize_remote.assert_not_called()
        apply_root.assert_not_called()
        self.assertEqual(self._snapshot_managed_tree(), before)
        self.assertFalse(future_source.target.exists())

    def test_google_credentials_failure_preserves_user_data_and_retry_completes(self) -> None:
        self._initial_apply()
        for target in (self.data_root, *(profile.target for profile in self.manifest.profiles)):
            env_path = target / ".env"
            env_path.write_bytes(b"user-owned \xff content is never parsed\n")
            env_path.chmod(0o640)
        user_data = self._snapshot_user_data()
        desired_root = managed_source_config(
            self.manifest, "default", "root", "retry-update"
        )
        self._commit(
            "root",
            {
                "root-distribution.yaml": self._root_manifest(
                    ["config.yaml", "retired.md"], "0.2.0"
                ),
                "config.yaml": desired_root,
            },
            "update root before retry",
        )
        credentials = self.data_root / "google-calendar-mcp"
        oauth_path = credentials / "gcp-oauth.keys.json"
        oauth_path.write_text("stale credentials\n", encoding="utf-8")
        tokens_path = credentials / "tokens.json"
        tokens_path.write_text("stale tokens\n", encoding="utf-8")
        profile_configs = {
            profile.target / "config.yaml": (profile.target / "config.yaml").read_bytes()
            for profile in self.manifest.profiles
        }
        checkout = self.data_root / "shared" / "lifelog"
        local_change = checkout / "retry-update.md"
        local_change.write_text("remote change survives local failure\n", encoding="utf-8")
        remote_before = run_git(
            "--git-dir", str(self.source_remotes["lifelog"]), "rev-parse", "main"
        )
        profile_heads = {
            name: run_git("--git-dir", str(self.source_remotes[name]), "rev-parse", "main")
            for name in PROFILE_NAMES
        }
        real_write = google_calendar._atomic_write
        written: list[Path] = []

        def write_then_fail(path: Path, content: bytes, mode: int) -> None:
            if path.name == "tokens.json":
                raise OSError("fixture Google credentials failure")
            real_write(path, content, mode)
            written.append(path)

        with (
            self._patched_runtime(),
            mock.patch.object(google_calendar, "_atomic_write", side_effect=write_then_fail),
            self.assertRaisesRegex(ApplyError, "could not install Google Calendar credentials"),
        ):
            app.apply(PRODUCTION_MANIFEST, self._payload())

        self.assertEqual(written, [oauth_path])
        self.assertIn("installed", json.loads(oauth_path.read_text(encoding="utf-8")))
        self.assertEqual(tokens_path.read_text(encoding="utf-8"), "stale tokens\n")
        self.assertEqual((self.data_root / "config.yaml").read_text(encoding="utf-8"), desired_root)
        self.assertEqual(self._snapshot_user_data(), user_data)
        self.assertEqual({path: path.read_bytes() for path in profile_configs}, profile_configs)
        completed_remote = run_git(
            "--git-dir", str(self.source_remotes["lifelog"]), "rev-parse", "main"
        )
        self.assertNotEqual(completed_remote, remote_before)
        self.assertEqual(local_change.read_text(encoding="utf-8"), "remote change survives local failure\n")
        self.assertEqual(
            {
                name: run_git("--git-dir", str(self.source_remotes[name]), "rev-parse", "main")
                for name in PROFILE_NAMES
            },
            profile_heads,
        )
        self._initial_apply()
        self.assertEqual(self._snapshot_user_data(), user_data)
        self.assertEqual(self._validate()["status"], "valid")
        self.assertEqual(
            run_git("--git-dir", str(self.source_remotes["lifelog"]), "rev-parse", "main"),
            completed_remote,
        )

    def _snapshot_user_data(self) -> dict[str, tuple[str, bytes | str, int]]:
        snapshot: dict[str, tuple[str, bytes | str, int]] = {}
        for path in sorted(self.data_root.rglob("*")):
            relative = path.relative_to(self.data_root)
            parts = relative.parts
            if not (
                relative.as_posix() == ".env"
                or (len(parts) == 3 and parts[0] == "profiles" and parts[2] == ".env")
                or parts[0] in PROFILE_USER_DIRECTORIES
                or (
                    len(parts) > 2
                    and parts[0] == "profiles"
                    and parts[2] in PROFILE_USER_DIRECTORIES
                )
            ):
                continue
            if path.is_symlink():
                snapshot[relative.as_posix()] = ("symlink", os.readlink(path), self._mode(path))
            elif path.is_file():
                snapshot[relative.as_posix()] = ("file", path.read_bytes(), self._mode(path))
            elif path.is_dir():
                snapshot[relative.as_posix()] = ("dir", b"", self._mode(path))
        return snapshot

    def _ensure_profile_locks(self) -> None:
        for profile in PROFILE_NAMES:
            lock = (
                self.data_root
                / "locks"
                / "repositories"
                / f"profile-{profile}.lock"
            )
            lock.parent.mkdir(parents=True, exist_ok=True)
            lock.touch(exist_ok=True)
            lock.chmod(0o600)

    def _snapshot_managed_tree(
        self,
    ) -> dict[str, tuple[str, int, bytes | str | None]]:
        ignored = (
            "locks",
            ".hermes-bootstrap-",
            ".hermes-repository-",
        )
        return {
            path: (entry.kind, entry.mode, entry.payload)
            for path, entry in self._snapshot_tree(self.data_root).items()
            if path != "."
            and ".git" not in path.split("/")
            and not any(
                path == root
                or path.startswith(f"{root}/")
                or path.startswith(root)
                for root in ignored
            )
        }

    @staticmethod
    def _snapshot_tree(
        root: Path, *, include_root: bool = True
    ) -> dict[str, TreeEntry]:
        paths = list(root.rglob("*"))
        if include_root:
            paths.append(root)
        snapshot: dict[str, TreeEntry] = {}
        for path in sorted(paths, key=lambda item: item.as_posix()):
            metadata = path.lstat()
            relative = "." if path == root else path.relative_to(root).as_posix()
            if stat.S_ISLNK(metadata.st_mode):
                kind = "symlink"
                payload: bytes | str | None = os.readlink(path)
            elif stat.S_ISREG(metadata.st_mode):
                kind = "file"
                payload = path.read_bytes()
            elif stat.S_ISDIR(metadata.st_mode):
                kind = "directory"
                payload = None
            else:
                kind = "special"
                payload = None
            snapshot[relative] = TreeEntry(
                kind=kind,
                mode=stat.S_IMODE(metadata.st_mode),
                payload=payload,
            )
        return snapshot


if __name__ == "__main__":
    unittest.main()
