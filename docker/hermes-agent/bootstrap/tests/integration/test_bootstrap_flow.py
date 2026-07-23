"""Repeatable end-to-end coverage for the Hermes bootstrap runtime."""

from __future__ import annotations

import base64
import io
import json
import os
import signal
import stat
import subprocess
import sys
import tempfile
import threading
import unittest
from contextlib import contextmanager, redirect_stderr, redirect_stdout
from dataclasses import dataclass, replace
from hashlib import sha256, sha384
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Iterator
from unittest import mock

from hermes_cli import profile_distribution


BOOTSTRAP_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(BOOTSTRAP_ROOT))

from hermes_bootstrap import app, cli
from hermes_bootstrap.errors import ApplyError, CredentialError, RepositoryError
from hermes_bootstrap.envfiles import GITHUB_KEYS, read_environment_values
from hermes_bootstrap.git import StagedSource, stage_distribution
from hermes_bootstrap.github import GitHubClient
from hermes_bootstrap.manifest import load_manifest
from hermes_bootstrap.models import BootstrapManifest, DistributionSource, SharedRepository
from hermes_bootstrap.payload import SCHEMA_VERSION


FIXTURE_TOKEN = "fixture-token-only"
API_URL_ENV = "HERMES_BOOTSTRAP_GITHUB_API_URL"
HOST_SECRET_ENV = "HERMES_BOOTSTRAP_TEST_HOST_SECRET"
HOST_SECRET_VALUE = "planted-host-secret-marker"
PRODUCTION_MANIFEST = BOOTSTRAP_ROOT.parent / "bootstrap-manifest.yaml"
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
SAFE_PATH = "/usr/bin:/bin"
PROCESS_TIMEOUT_SECONDS = 15.0
PROCESS_STOP_TIMEOUT_SECONDS = 2.0
SERVER_STOP_TIMEOUT_SECONDS = 2.0
_REAL_POPEN = subprocess.Popen
_CHILD_PROCESSES: list[subprocess.Popen[object]] = []


@dataclass(frozen=True)
class TreeEntry:
    kind: str
    mode: int
    device: int
    inode: int
    links: int
    size: int
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
        self.server.daemon_threads = True
        self.server.block_on_close = False
        ready = threading.Event()

        def serve() -> None:
            ready.set()
            assert self.server is not None
            self.server.serve_forever(poll_interval=0.05)

        self.thread = threading.Thread(target=serve, daemon=True)
        self.thread.start()
        if not ready.wait(timeout=SERVER_STOP_TIMEOUT_SECONDS):
            self.server.server_close()
            raise AssertionError("fixture GitHub server did not start")
        return self

    @property
    def url(self) -> str:
        assert self.server is not None
        host, port = self.server.server_address
        return f"http://{host}:{port}"

    def __exit__(self, *_args: object) -> None:
        assert self.server is not None and self.thread is not None
        shutdown = threading.Thread(target=self.server.shutdown, daemon=True)
        shutdown.start()
        shutdown.join(timeout=SERVER_STOP_TIMEOUT_SECONDS)
        self.server.server_close()
        self.thread.join(timeout=SERVER_STOP_TIMEOUT_SECONDS)
        if shutdown.is_alive() or self.thread.is_alive():
            raise AssertionError("fixture GitHub server did not stop")


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
        self.generated_secret_counter = 0
        self.data_root = self.fixture_root / "data"
        self.data_root.mkdir()
        app.Transaction.recover_if_needed(self.data_root)
        self.remotes = self.fixture_root / "remotes"
        self.seed_root = self.fixture_root / "seeds"
        self.remotes.mkdir()
        self.seed_root.mkdir()
        self.seeds: dict[str, Path] = {}
        self.source_remotes: dict[str, Path] = {}
        self._create_sources()
        self.manifest = self._local_manifest()
        self.transport_remotes = {
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
                "config.yaml": "root: initial\n",
                "retired.md": "retire me\n",
            },
        )
        for profile in PROFILE_NAMES:
            self._create_distribution(
                profile,
                {
                    ".gitignore": self._profile_gitignore(),
                    "distribution.yaml": self._profile_manifest(profile),
                    "config.yaml": f"profile: {profile}-initial\n",
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
        root = replace(parsed.root_distribution, target=self.data_root)
        profiles = tuple(
            replace(
                source,
                target=self.data_root / "profiles" / source.name,
            )
            for source in parsed.profiles
        )
        repositories = tuple(
            replace(
                repository,
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
                    "distribution.yaml": self._profile_manifest(profile),
                    "config.yaml": f"profile: {profile}-initial\n",
                    "SOUL.md": f"{profile} initial\n",
                    "memories/runtime.txt": f"{profile} memory\n",
                    "sessions/runtime.txt": f"{profile} session\n",
                    ".env": f"# {profile} comment\nCUSTOM_{profile.upper()}=keep\n",
                },
            )

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
    def _profile_manifest(name: str, version: str = "0.1.0") -> str:
        return "\n".join(
            [
                f"name: {name}",
                f"version: {version}",
                "hermes_requires: '>=0.18.2'",
                "distribution_owned:",
                "- SOUL.md",
                "- config.yaml",
                "",
            ]
        )

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
        return run_git("rev-parse", "HEAD", cwd=seed)

    def _payload(self, token: str = FIXTURE_TOKEN) -> io.StringIO:
        records: list[dict[str, object]] = [{"type": "header", "schema_version": SCHEMA_VERSION}]
        values = {
            "dashboard": {"username": "fixture-user", "password": "fixture-password"},
            "github": {"credential": token},
            "slack_default": {
                "bot_token": "xoxb-default-bot",
                "app_token": "xapp-default-app",
                "allowed_users": "UDEFAULT",
            },
            "slack_rick": {
                "bot_token": "xoxb-rick-bot",
                "app_token": "xapp-rick-app",
                "allowed_users": "URICK",
            },
            "slack_hoffman": {
                "bot_token": "xoxb-hoffman-bot",
                "app_token": "xapp-hoffman-app",
                "allowed_users": "UHOFFMAN",
            },
            "slack_risarisa": {
                "bot_token": "xoxb-risarisa-bot",
                "app_token": "xapp-risarisa-app",
                "allowed_users": "URISARISA",
            },
            "slack_nancy": {
                "bot_token": "xoxb-nancy-bot",
                "app_token": "xapp-nancy-app",
                "allowed_users": "UNANCY",
            },
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
        production_source_identity = app._source_identity
        api_identities: set[tuple[str, str]] = set()
        for source in (
            self.manifest.root_distribution,
            *self.manifest.profiles,
            *self.manifest.shared_repositories,
        ):
            identity = production_source_identity(source.source)
            if identity is not None:
                api_identities.add(identity)

        with FixtureGitHub(api_identities) as github:
            runtime_environment = _minimal_environment(self.child_home)
            environment_with_api = {
                **runtime_environment,
                API_URL_ENV: github.url,
            }

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
                    and command[0] == "/usr/bin/git"
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
                if child_arguments[0] == "/usr/bin/git":
                    environment = self._redirect_git_transport(environment)
                    kwargs["env"] = environment
                process = _REAL_POPEN(*args, **kwargs)  # type: ignore[arg-type]
                _CHILD_PROCESSES.append(process)
                return process

            with mock.patch.dict(os.environ, environment_with_api, clear=True):
                api_base = os.environ.pop(API_URL_ENV)

                def client_factory(auth: object) -> GitHubClient:
                    return GitHubClient(auth, api_base=api_base)  # type: ignore[arg-type]

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
                    mock.patch.object(app, "GitHubClient", side_effect=client_factory),
                    mock.patch.object(
                        app, "stage_distribution", side_effect=audited_stage
                    ),
                    mock.patch.object(subprocess, "Popen", side_effect=audited_popen),
                    mock.patch.object(tempfile, "tempdir", str(self.profile_tmpdir)),
                    mock.patch("hermes_bootstrap.envfiles.hash_password", return_value="fixture-password-hash"),
                    mock.patch(
                        "hermes_bootstrap.envfiles.secrets.token_urlsafe",
                        side_effect=self._next_fixture_secret,
                    ),
                ):
                    yield

    def _redirect_git_transport(
        self, environment: dict[str, str]
    ) -> dict[str, str]:
        redirected = dict(environment)
        first = int(redirected.get("GIT_CONFIG_COUNT", "0"))
        for offset, (source, remote) in enumerate(self.transport_remotes.items()):
            index = first + offset
            redirected[f"GIT_CONFIG_KEY_{index}"] = (
                f"url.{remote.as_posix()}.insteadOf"
            )
            redirected[f"GIT_CONFIG_VALUE_{index}"] = source
        redirected["GIT_CONFIG_COUNT"] = str(first + len(self.transport_remotes))
        return redirected

    def _next_fixture_secret(self, nbytes: int) -> str:
        self.assertEqual(nbytes, 48)
        self.generated_secret_counter += 1
        digest = sha384(f"fixture-secret-{self.generated_secret_counter}".encode()).digest()
        return base64.urlsafe_b64encode(digest).decode("ascii")

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
        journals = self.data_root / ".bootstrap" / "transactions"
        if journals.exists():
            leaks.update(
                path.relative_to(self.data_root).as_posix()
                for path in journals.iterdir()
                if path.name != ".lock"
            )
        self.assertEqual(sorted(leaks), [])
        self.assertEqual(
            self._snapshot_tree(self.profile_tmpdir, include_root=False),
            self.profile_tmpdir_before,
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
        self.assertFalse(os.path.lexists(legacy))
        self.assertEqual(self._validate()["status"], "valid")
        leak = lifelog / "nested" / "askpass-review-probe"
        leak.parent.mkdir()
        leak.write_text("probe\n", encoding="utf-8")
        try:
            with self.assertRaises(AssertionError):
                self._assert_no_temporary_resources()
        finally:
            leak.unlink()
            leak.parent.rmdir()
        profile_leak = self.profile_tmpdir / "hermes-profile-source-review-probe"
        profile_leak.mkdir()
        try:
            with self.assertRaises(AssertionError):
                self._assert_no_temporary_resources()
        finally:
            profile_leak.rmdir()
        for prefix in (
            ".hermes-profile-snapshots-",
            ".hermes-profile-sync-",
        ):
            production_leak = self.data_root / f"{prefix}review-probe"
            production_leak.mkdir()
            try:
                with self.subTest(prefix=prefix):
                    with self.assertRaises(AssertionError):
                        self._assert_no_temporary_resources()
            finally:
                production_leak.rmdir()

    def test_profile_targets_keep_canonical_source_token_and_manifest_identity(self) -> None:
        production_profiles = {
            source.name: source for source in load_manifest(PRODUCTION_MANIFEST).profiles
        }
        self.assertEqual(
            tuple(
                (source.name, source.source, source.ref)
                for source in self.manifest.profiles
            ),
            tuple(
                (source.name, source.source, source.ref)
                for source in production_profiles.values()
            ),
        )
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
            command_stdout.getvalue(),
            '{"profile_sync":{"hoffman":"unchanged","nancy":"unchanged",'
            '"rick":"unchanged","risarisa":"unchanged"},'
            '"profiles":["rick","hoffman","risarisa","nancy"],'
            '"repositories":["lifelog"],"status":"applied"}\n',
        )
        self.assertEqual(command_stderr.getvalue(), "")
        self.assertEqual(ambient_stdout.getvalue(), "")
        # The pinned hermes_cli emits deprecation warnings here; the leak scan
        # above still treats ambient stderr as protected output.

        declared_sources = (
            self.manifest.root_distribution,
            *self.manifest.profiles,
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

        self.assertEqual(
            [
                name
                for name, _source, _ref, _staged_commit, _head
                in self.profile_stage_refs
            ],
            list(PROFILE_NAMES),
        )
        for (
            name,
            source,
            ref,
            staged_commit,
            remote_head,
        ) in self.profile_stage_refs:
            with self.subTest(staged_profile=name):
                self.assertEqual(source, production_profiles[name].source)
                self.assertEqual(ref, remote_head)
                self.assertEqual(staged_commit, ref)
                self.assertRegex(ref, r"\A[0-9a-f]{40}(?:[0-9a-f]{24})?\Z")

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
                token = read_environment_values(target / ".env", GITHUB_KEYS)["GH_TOKEN"]
                self.assertEqual(sha256(token.encode("utf-8")).digest(), sha256(FIXTURE_TOKEN.encode("utf-8")).digest())

    def test_identical_second_apply_preserves_the_target_and_runtime_tree(self) -> None:
        self._initial_apply()
        before = self._snapshot_managed_tree()
        locks_before = self._snapshot_coordination_locks()
        owned = self.data_root / "config.yaml"
        root_sentinel = self.data_root / "memories" / "root.txt"
        profile_sentinel = (
            self.data_root / "profiles" / "rick" / "memories" / "runtime.txt"
        )

        def file_identity(path: Path) -> tuple[int, int, bytes, int]:
            metadata = path.stat()
            return (
                metadata.st_dev,
                metadata.st_ino,
                path.read_bytes(),
                self._mode(path),
            )

        identities_before = {
            "owned": file_identity(owned),
            "root_sentinel": file_identity(root_sentinel),
            "profile_sentinel": file_identity(profile_sentinel),
        }
        lifelog = self.data_root / "shared" / "lifelog"
        lifelog_head = run_git("rev-parse", "HEAD", cwd=lifelog)
        lifelog_commits = run_git("rev-list", "--count", "HEAD", cwd=lifelog)

        self._initial_apply()

        self.assertEqual(self._snapshot_managed_tree(), before)
        self.assertEqual(self._snapshot_coordination_locks(), locks_before)
        self.assertEqual(file_identity(owned), identities_before["owned"])
        self.assertEqual(
            file_identity(root_sentinel), identities_before["root_sentinel"]
        )
        self.assertEqual(
            file_identity(profile_sentinel), identities_before["profile_sentinel"]
        )
        self.assertEqual(run_git("rev-parse", "HEAD", cwd=lifelog), lifelog_head)
        self.assertEqual(run_git("rev-list", "--count", "HEAD", cwd=lifelog), lifelog_commits)

    def test_local_profile_update_publishes_and_preserves_runtime_content(self) -> None:
        self._initial_apply()
        target = self.data_root / "profiles" / "rick"
        runtime = target / "memories" / "runtime.txt"
        runtime_before = (runtime.stat().st_ino, runtime.read_bytes(), self._mode(runtime))
        remote_before = run_git(
            "--git-dir", str(self.source_remotes["rick"]), "rev-parse", "main"
        )
        self._write_files(
            target,
            {
                "distribution.yaml": self._profile_manifest("rick", "0.2.0"),
                "config.yaml": "profile: rick-updated\n",
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
        self.assertEqual((target / "config.yaml").read_text(encoding="utf-8"), "profile: rick-updated\n")
        self.assertEqual(
            (runtime.stat().st_ino, runtime.read_bytes(), self._mode(runtime)),
            runtime_before,
        )
        self.assertEqual((target / "sessions" / "runtime.txt").read_text(encoding="utf-8"), "rick session\n")
        self.assertNotEqual(
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

    def test_legacy_lifelog_checkout_migrates_to_canonical_relative_link(self) -> None:
        legacy = self.data_root / "core" / "lifelog"
        legacy.parent.mkdir(parents=True)
        run_git(
            "clone",
            "--no-hardlinks",
            "--branch",
            "main",
            str(self.source_remotes["lifelog"]),
            str(legacy),
        )
        lifelog_source = next(
            repository.source
            for repository in self.manifest.shared_repositories
            if repository.name == "lifelog"
        )
        run_git("remote", "set-url", "origin", lifelog_source, cwd=legacy)
        run_git("config", "user.name", "Fixture", cwd=legacy)
        run_git("config", "user.email", "fixture@example.test", cwd=legacy)
        run_git(
            "config",
            "--local",
            "hermes.fixture-migration-id",
            "legacy-checkout-only",
            cwd=legacy,
        )
        legacy_head = run_git("rev-parse", "HEAD", cwd=legacy)
        legacy_metadata = legacy.stat()
        legacy_identity = (legacy_metadata.st_dev, legacy_metadata.st_ino)

        self._initial_apply()

        canonical = self.data_root / "shared" / "lifelog"
        self.assertTrue((canonical / ".git").is_dir())
        canonical_metadata = canonical.stat()
        self.assertNotEqual(
            (canonical_metadata.st_dev, canonical_metadata.st_ino), legacy_identity
        )
        self.assertEqual(
            run_git(
                "config",
                "--local",
                "--get",
                "hermes.fixture-migration-id",
                cwd=canonical,
            ),
            "legacy-checkout-only",
        )
        self.assertEqual(run_git("rev-parse", "HEAD", cwd=canonical), legacy_head)
        self.assertEqual((canonical / "README.md").read_text(encoding="utf-8"), "initial lifelog\n")
        self.assertFalse(os.path.lexists(legacy))

    def test_conflicting_real_lifelog_paths_return_exit_five_without_mutating_the_tree(self) -> None:
        legacy = self.data_root / "core" / "lifelog"
        canonical = self.data_root / "shared" / "lifelog"
        for checkout in (legacy, canonical):
            checkout.parent.mkdir(parents=True, exist_ok=True)
            run_git(
                "clone",
                "--no-hardlinks",
                "--branch",
                "main",
                str(self.source_remotes["lifelog"]),
                str(checkout),
            )
        self._ensure_repository_lock()
        before = self._snapshot_tree(self.data_root)
        locks_before = self._snapshot_coordination_locks()
        remote_before = run_git("--git-dir", str(self.source_remotes["lifelog"]), "rev-parse", "main")
        stdout = io.StringIO()
        stderr = io.StringIO()

        with self._patched_runtime():
            sync_exit_code = cli.main(
                [
                    "sync-repository",
                    "lifelog",
                    "--manifest",
                    str(PRODUCTION_MANIFEST),
                ],
                stdout=stdout,
                stderr=stderr,
                environ={"GH_TOKEN": FIXTURE_TOKEN},
            )

        self.assertEqual(sync_exit_code, 5)
        self.assertEqual(stdout.getvalue(), "")
        self._assert_no_protected_output(stderr.getvalue(), "failed sync output")
        self.assertEqual(
            self._snapshot_tree_contract(self._snapshot_tree(self.data_root)),
            self._snapshot_tree_contract(before),
        )
        self.assertEqual(
            run_git("--git-dir", str(self.source_remotes["lifelog"]), "rev-parse", "main"),
            remote_before,
        )
        self.assertEqual(self._snapshot_coordination_locks(), locks_before)

        stdout = io.StringIO()
        stderr = io.StringIO()
        with self._patched_runtime():
            exit_code = cli.main(
                ["apply", "--manifest", str(PRODUCTION_MANIFEST)],
                stdin=self._payload(),
                stdout=stdout,
                stderr=stderr,
            )

        self.assertEqual(exit_code, 5)
        self.assertEqual(stdout.getvalue(), "")
        self._assert_no_protected_output(stderr.getvalue(), "failed apply output")
        self.assertEqual(self._snapshot_tree_contract(self._snapshot_tree(self.data_root)), self._snapshot_tree_contract(before))
        self.assertEqual(self._snapshot_coordination_locks(), locks_before)

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
        before = self._snapshot_tree(self.data_root)
        self.assertIn(".bootstrap/transactions/.lock", before)

        with self.assertRaises(CredentialError):
            self._apply("invalid-fixture-token")

        after = self._snapshot_tree(self.data_root)
        self.assertEqual(after, before)
        journal = self.data_root / ".bootstrap" / "transactions"
        self.assertFalse(journal.exists() and any(path.name != ".lock" for path in journal.iterdir()))

    def test_runtime_failpoints_rollback_each_mutation_phase_without_reversing_remote_pushes(self) -> None:
        self._initial_apply()
        phases = (
            "root-apply",
            "profile-apply:rick",
            "profile-apply:hoffman",
            "profile-apply:risarisa",
            "profile-apply:nancy",
            "shared-apply:lifelog",
            "env-merge:default",
            "env-merge:rick",
            "env-merge:hoffman",
            "env-merge:risarisa",
            "env-merge:nancy",
            "final-validation",
            "commit-cleanup",
        )
        managed_env_keys = frozenset(
            {
                "GH_TOKEN",
                "GITHUB_TOKEN",
                "GITHUB_PERSONAL_ACCESS_TOKEN",
                "HERMES_DASHBOARD_BASIC_AUTH_USERNAME",
                "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH",
                "HERMES_DASHBOARD_BASIC_AUTH_SECRET",
                "API_SERVER_KEY",
                "SLACK_BOT_TOKEN",
                "SLACK_APP_TOKEN",
                "SLACK_ALLOWED_USERS",
            }
        )
        env_paths = {
            "default": ".env",
            **{
                profile: f"profiles/{profile}/.env"
                for profile in PROFILE_NAMES
            },
        }
        unmanaged_env_markers = {
            "default": b"CUSTOM_ROOT=keep",
            **{
                profile: f"CUSTOM_{profile.upper()}=keep".encode("utf-8")
                for profile in PROFILE_NAMES
            },
        }
        canonical = self.data_root / "shared" / "lifelog"
        legacy = self.data_root / "core" / "lifelog"

        def reset_phase_fixture() -> list[Exception]:
            errors: list[Exception] = []
            try:
                self._initial_apply()
            except Exception as error:
                errors.append(error)
            try:
                self._assert_no_live_children()
            except Exception as error:
                errors.append(error)
            return errors

        for revision, phase in enumerate(phases, start=2):
            with self.subTest(phase=phase):
                try:
                    version = f"0.{revision}.0"
                    desired_root = f"root: rollback-{revision}\n"
                    desired_profiles = {
                        profile: f"profile: {profile}-rollback-{revision}\n"
                        for profile in PROFILE_NAMES
                    }
                    self._commit(
                        "root",
                        {
                            "root-distribution.yaml": self._root_manifest(
                                ["config.yaml", "retired.md"], version
                            ),
                            "config.yaml": desired_root,
                        },
                        f"rollback root {revision}",
                    )
                    profile_remote_before = {
                        profile: run_git(
                            "--git-dir",
                            str(self.source_remotes[profile]),
                            "rev-parse",
                            "main",
                        )
                        for profile in PROFILE_NAMES
                    }
                    for profile in PROFILE_NAMES:
                        self._write_files(
                            self.data_root / "profiles" / profile,
                            {
                                "distribution.yaml": self._profile_manifest(
                                    profile, version
                                ),
                                "config.yaml": desired_profiles[profile],
                            },
                        )

                    stale_marker = f"stale-managed-{revision}".encode("utf-8")
                    for profile, relative in env_paths.items():
                        path = self.data_root / relative
                        stale_lines: list[str] = []
                        replaced: set[str] = set()
                        for line in path.read_text(encoding="utf-8").splitlines():
                            key, separator, _value = line.partition("=")
                            if separator and key in managed_env_keys:
                                line = f"{key}=stale-managed-{revision}-{profile}"
                                replaced.add(key)
                            stale_lines.append(line)
                        if "API_SERVER_KEY" not in replaced:
                            stale_lines.append(
                                f"API_SERVER_KEY=stale-managed-{revision}-{profile}"
                            )
                            replaced.add("API_SERVER_KEY")
                        self.assertEqual(replaced, managed_env_keys)
                        self.assertTrue(
                            unmanaged_env_markers[profile]
                            in "\n".join(stale_lines).encode("utf-8"),
                            "stale environment lost unmanaged content",
                        )
                        path.write_text(
                            "\n".join(stale_lines) + "\n", encoding="utf-8"
                        )
                        self.assertEqual(self._mode(path), 0o600)

                    self.assertTrue(canonical.is_dir())
                    self.assertFalse(os.path.lexists(legacy))
                    legacy.parent.mkdir(parents=True, exist_ok=True)
                    canonical.rename(legacy)
                    lifelog_change = legacy / f"rollback-{revision}.md"
                    lifelog_change.write_text(
                        f"remote change {revision}\n", encoding="utf-8"
                    )
                    remote_before = run_git(
                        "--git-dir",
                        str(self.source_remotes["lifelog"]),
                        "rev-parse",
                        "main",
                    )
                    transaction_tree: dict[str, TreeEntry] | None = None
                    transaction_remote: str | None = None
                    observed_failpoints: list[str] = []
                    mutation_assertion: AssertionError | None = None
                    mutation_verified = False
                    real_begin = app.Transaction.begin

                    def begin(data_root: Path) -> object:
                        nonlocal transaction_remote, transaction_tree
                        transaction_tree = self._snapshot_tree(self.data_root)
                        transaction_remote = run_git(
                            "--git-dir",
                            str(self.source_remotes["lifelog"]),
                            "rev-parse",
                            "main",
                        )
                        return real_begin(data_root)

                    def baseline_entry(relative: str) -> TreeEntry:
                        self.assertIsNotNone(transaction_tree)
                        assert transaction_tree is not None
                        entry = transaction_tree.get(relative)
                        self.assertIsNotNone(
                            entry, f"transaction baseline omitted {relative}"
                        )
                        assert entry is not None
                        return entry

                    def assert_owned_file_mutated(
                        relative: str, expected: str
                    ) -> None:
                        before = baseline_entry(relative)
                        path = self.data_root / relative
                        self.assertEqual(before.kind, "file")
                        self.assertTrue(path.is_file())
                        current = path.read_bytes()
                        self.assertNotEqual(current, before.payload)
                        self.assertEqual(current, expected.encode("utf-8"))

                    def assert_owned_file_unchanged(
                        relative: str, expected: str
                    ) -> None:
                        before = baseline_entry(relative)
                        path = self.data_root / relative
                        self.assertEqual(before.kind, "file")
                        self.assertTrue(path.is_file())
                        current = path.read_bytes()
                        self.assertEqual(current, before.payload)
                        self.assertEqual(current, expected.encode("utf-8"))

                    def assert_environment_mutated(profile: str) -> None:
                        relative = env_paths[profile]
                        before = baseline_entry(relative)
                        path = self.data_root / relative
                        self.assertEqual(before.kind, "file")
                        self.assertTrue(path.is_file())
                        current = path.read_bytes()
                        self.assertFalse(
                            current == before.payload,
                            f"{profile} environment merge was a no-op",
                        )
                        self.assertTrue(
                            unmanaged_env_markers[profile] in current,
                            f"{profile} environment lost unmanaged content",
                        )

                    def assert_shared_repository_mutated() -> None:
                        before = baseline_entry("core/lifelog")
                        assert transaction_tree is not None
                        self.assertEqual(before.kind, "directory")
                        self.assertNotIn("shared/lifelog", transaction_tree)
                        self.assertTrue(canonical.is_dir())
                        self.assertFalse(os.path.lexists(legacy))
                        metadata = canonical.stat()
                        self.assertNotEqual(
                            (metadata.st_dev, metadata.st_ino),
                            (before.device, before.inode),
                        )

                    def assert_all_representative_mutations() -> None:
                        assert_owned_file_mutated("config.yaml", desired_root)
                        for profile in PROFILE_NAMES:
                            assert_owned_file_unchanged(
                                f"profiles/{profile}/config.yaml",
                                desired_profiles[profile],
                            )
                        assert_shared_repository_mutated()
                        for profile in env_paths:
                            assert_environment_mutated(profile)

                    def assert_selected_phase_mutated(name: str) -> None:
                        if name == "root-apply":
                            assert_owned_file_mutated("config.yaml", desired_root)
                        elif name.startswith("profile-apply:"):
                            profile = name.partition(":")[2]
                            assert_owned_file_unchanged(
                                f"profiles/{profile}/config.yaml",
                                desired_profiles[profile],
                            )
                        elif name == "shared-apply:lifelog":
                            assert_shared_repository_mutated()
                        elif name.startswith("env-merge:"):
                            assert_environment_mutated(name.partition(":")[2])
                        else:
                            self.assertIn(
                                name, {"final-validation", "commit-cleanup"}
                            )
                            assert_all_representative_mutations()

                    def failpoint(name: str, selected: str = phase) -> None:
                        nonlocal mutation_assertion, mutation_verified
                        observed_failpoints.append(name)
                        if name == selected:
                            try:
                                assert_selected_phase_mutated(name)
                                mutation_verified = True
                            except AssertionError as error:
                                mutation_assertion = error
                            raise ApplyError("fixture failure")

                    with (
                        self._patched_runtime(),
                        mock.patch.object(app.Transaction, "begin", side_effect=begin),
                        mock.patch.object(app, "_failpoint", side_effect=failpoint),
                    ):
                        with self.assertRaises(ApplyError):
                            app.apply(PRODUCTION_MANIFEST, self._payload())

                    if mutation_assertion is not None:
                        raise mutation_assertion
                    self.assertTrue(
                        mutation_verified,
                        f"{phase} did not verify a real target mutation",
                    )
                    self.assertIsNotNone(transaction_tree)
                    self.assertIsNotNone(transaction_remote)
                    assert transaction_tree is not None
                    assert transaction_remote is not None
                    self.assertNotEqual(
                        baseline_entry("config.yaml").payload,
                        desired_root.encode("utf-8"),
                    )
                    for profile in PROFILE_NAMES:
                        self.assertEqual(
                            baseline_entry(
                                f"profiles/{profile}/config.yaml"
                            ).payload,
                            desired_profiles[profile].encode("utf-8"),
                        )
                    for relative in env_paths.values():
                        payload = baseline_entry(relative).payload
                        self.assertIsInstance(payload, bytes)
                        assert isinstance(payload, bytes)
                        self.assertTrue(
                            stale_marker in payload,
                            "transaction baseline environment was not stale",
                        )
                    self.assertEqual(
                        baseline_entry("core/lifelog").kind, "directory"
                    )
                    self.assertNotIn("shared/lifelog", transaction_tree)
                    self.assertEqual(
                        baseline_entry(
                            f"core/lifelog/rollback-{revision}.md"
                        ).payload,
                        f"remote change {revision}\n".encode("utf-8"),
                    )
                    self.assertIn(
                        ".bootstrap/transactions/.lock", transaction_tree
                    )
                    self.assertIn(
                        "locks/repositories/lifelog.lock", transaction_tree
                    )
                    self.assertTrue(
                        any(".git" in path.split("/") for path in transaction_tree)
                    )
                    self.assertTrue(
                        self._snapshot_rollback_contract(
                            self._snapshot_tree(self.data_root)
                        )
                        == self._snapshot_rollback_contract(transaction_tree),
                        "rollback did not restore the exact transaction baseline",
                    )
                    selected_index = phases.index(phase)
                    self.assertEqual(
                        tuple(observed_failpoints), phases[: selected_index + 1]
                    )
                    remote_after = run_git(
                        "--git-dir",
                        str(self.source_remotes["lifelog"]),
                        "rev-parse",
                        "main",
                    )
                    self.assertNotEqual(transaction_remote, remote_before)
                    self.assertEqual(remote_after, transaction_remote)
                    for profile in PROFILE_NAMES:
                        self.assertNotEqual(
                            run_git(
                                "--git-dir",
                                str(self.source_remotes[profile]),
                                "rev-parse",
                                "main",
                            ),
                            profile_remote_before[profile],
                        )
                except Exception as primary_error:
                    for cleanup_error in reset_phase_fixture():
                        primary_error.add_note(
                            f"phase cleanup also failed: {cleanup_error}"
                        )
                    raise
                cleanup_errors = reset_phase_fixture()
                if cleanup_errors:
                    primary_cleanup_error = cleanup_errors[0]
                    for cleanup_error in cleanup_errors[1:]:
                        primary_cleanup_error.add_note(
                            f"additional phase cleanup failure: {cleanup_error}"
                        )
                    raise primary_cleanup_error

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
            "API_SERVER_KEY",
            "SLACK_BOT_TOKEN",
            "SLACK_APP_TOKEN",
            "SLACK_ALLOWED_USERS",
        ):
            self.assertEqual(sum(line.startswith(f"{key}=") for line in root_env.splitlines()), 1)
        root_values = dict(
            line.partition("=")[::2]
            for line in root_env.splitlines()
            if "=" in line
        )
        self.assertNotEqual(
            root_values["API_SERVER_KEY"],
            root_values["HERMES_DASHBOARD_BASIC_AUTH_SECRET"],
        )

        for profile in PROFILE_NAMES:
            profile_env = (
                self.data_root / "profiles" / profile / ".env"
            ).read_text(encoding="utf-8")
            self.assertFalse(
                any(
                    line.startswith("API_SERVER_KEY=")
                    for line in profile_env.splitlines()
                )
            )

        original_api_key = root_values["API_SERVER_KEY"]
        root_path = self.data_root / ".env"
        root_path.write_text(
            root_path.read_text(encoding="utf-8")
            + f"API_SERVER_KEY={original_api_key}\n",
            encoding="utf-8",
        )
        for profile in PROFILE_NAMES:
            profile_path = self.data_root / "profiles" / profile / ".env"
            profile_path.write_text(
                profile_path.read_text(encoding="utf-8")
                + "API_SERVER_KEY=stale-named-profile-key\n",
                encoding="utf-8",
            )

        self.assertEqual(self._apply()["status"], "applied")

        refreshed_root = root_path.read_text(encoding="utf-8")
        refreshed_values = dict(
            line.partition("=")[::2]
            for line in refreshed_root.splitlines()
            if "=" in line
        )
        self.assertEqual(
            sum(
                line.startswith("API_SERVER_KEY=")
                for line in refreshed_root.splitlines()
            ),
            1,
        )
        self.assertNotEqual(refreshed_values["API_SERVER_KEY"], original_api_key)
        self.assertNotEqual(
            refreshed_values["API_SERVER_KEY"],
            refreshed_values["HERMES_DASHBOARD_BASIC_AUTH_SECRET"],
        )
        for profile in PROFILE_NAMES:
            profile_env = (
                self.data_root / "profiles" / profile / ".env"
            ).read_text(encoding="utf-8")
            self.assertNotIn("API_SERVER_KEY=", profile_env)

    def test_next_apply_recovers_crashed_durable_transaction_before_reading_payload(self) -> None:
        self._initial_apply()
        target = self.data_root / "config.yaml"
        expected = target.read_text(encoding="utf-8")
        script = (
            "from pathlib import Path; import os; "
            "from hermes_bootstrap.transaction import Transaction; "
            f"assert {HOST_SECRET_ENV!r} not in os.environ; "
            f"path=Path({str(target)!r}); tx=Transaction.begin(path.parents[0]); tx.snapshot(path); "
            "path.write_text('crashed mutation\\n', encoding='utf-8'); tx._release_lock(); os._exit(0)"
        )
        package_root = Path(app.__file__).resolve().parents[1]
        environment = _minimal_environment(
            self.child_home,
            PYTHONPATH=str(package_root),
            TMPDIR=str(self.profile_tmpdir),
        )
        self.assertNotIn(HOST_SECRET_ENV, environment)
        completed = _run_bounded(
            (sys.executable, "-c", script),
            environment=environment,
            timeout=5.0,
        )
        child_output = completed.stdout + completed.stderr
        self.assertFalse(
            HOST_SECRET_ENV in child_output,
            "recovery child output contained a protected host key",
        )
        self._assert_no_protected_output(child_output, "recovery child output")
        self.assertEqual(completed.returncode, 0, completed.stderr)
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
            if relative.startswith(
                (
                    ".bootstrap/transactions/",
                    ".hermes-bootstrap-",
                    ".hermes-repository-",
                )
            ):
                continue
            metadata = path.lstat()
            if path.is_symlink():
                snapshot[relative] = ("symlink", os.readlink(path), self._mode(path))
            elif path.is_file():
                snapshot[relative] = ("file", path.read_bytes(), self._mode(path))
            elif path.is_dir():
                snapshot[relative] = ("dir", b"", self._mode(path))
        return snapshot

    def _ensure_repository_lock(self) -> None:
        lock = self.data_root / "locks" / "repositories" / "lifelog.lock"
        lock.parent.mkdir(parents=True, exist_ok=True)
        lock.touch(exist_ok=True)
        lock.chmod(0o600)

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

    def _snapshot_coordination_locks(self) -> dict[str, TreeEntry | None]:
        tree = self._snapshot_tree(self.data_root)
        lock_paths = (
            ".bootstrap/transactions/.lock",
            "locks/repositories/lifelog.lock",
            *(
                f"locks/repositories/profile-{profile}.lock"
                for profile in PROFILE_NAMES
            ),
        )
        return {path: tree.get(path) for path in lock_paths}

    @staticmethod
    def _snapshot_tree_contract(
        tree: dict[str, TreeEntry],
    ) -> dict[str, tuple[str, int, int, int, bytes | str | None]]:
        return {
            path: (entry.kind, entry.mode, entry.links, entry.size, entry.payload)
            for path, entry in tree.items()
        }

    @staticmethod
    def _snapshot_rollback_contract(
        tree: dict[str, TreeEntry],
    ) -> dict[
        str, tuple[str, int, int, int | None, bytes | str | None]
    ]:
        contract: dict[
            str, tuple[str, int, int, int | None, bytes | str | None]
        ] = {}

        def is_temporary(path: str) -> bool:
            return any(
                part.startswith((".hermes-bootstrap-", ".hermes-repository-"))
                for part in path.split("/")
            )

        temporary_directory_children: dict[str, int] = {}
        for path, entry in tree.items():
            if entry.kind != "directory" or not is_temporary(path):
                continue
            parent = path.rpartition("/")[0] or "."
            if not is_temporary(parent):
                temporary_directory_children[parent] = (
                    temporary_directory_children.get(parent, 0) + 1
                )

        for path, entry in tree.items():
            if is_temporary(path):
                continue
            links = entry.links - temporary_directory_children.get(path, 0)
            # Directory st_size is allocator metadata after transient child entries;
            # retained type, mode, effective nlink, paths, bytes, and symlinks stay exact.
            directory_size = None if entry.kind == "directory" else entry.size
            contract[path] = (
                entry.kind,
                entry.mode,
                links,
                directory_size,
                entry.payload,
            )
        return contract

    def _snapshot_managed_tree(
        self,
    ) -> dict[str, tuple[str, int, int, int, bytes | str | None]]:
        ignored = (
            ".bootstrap/transactions",
            "locks",
            ".hermes-bootstrap-",
            ".hermes-repository-",
        )
        return {
            path: (entry.kind, entry.mode, entry.links, entry.size, entry.payload)
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
                device=metadata.st_dev,
                inode=metadata.st_ino,
                links=metadata.st_nlink,
                size=metadata.st_size,
                payload=payload,
            )
        return snapshot


if __name__ == "__main__":
    unittest.main()
