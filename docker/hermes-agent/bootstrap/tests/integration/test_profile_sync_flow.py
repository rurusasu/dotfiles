"""End-to-end local-first profile publication coverage."""

from __future__ import annotations

import base64
import hashlib
import io
import json
import shutil
import stat
import subprocess
import unittest
from builtins import BaseExceptionGroup, ExceptionGroup
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path, PurePosixPath
from types import FrameType, TracebackType
from unittest import mock

import yaml
from hermes_cli import profile_distribution

try:
    from . import test_bootstrap_flow as bootstrap_flow
except ImportError:
    import test_bootstrap_flow as bootstrap_flow

from hermes_bootstrap import cli, profile_snapshot, profile_sync
from hermes_bootstrap.errors import ApplyError, RepositoryError, ValidationError
from hermes_bootstrap.models import DistributionSource


PNG_FIXTURE = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk"
    "+A8AAQUBAScY42YAAAAASUVORK5CYII="
)


class ProfileSyncFlowTests(unittest.TestCase):
    def setUp(self) -> None:
        self.flow = bootstrap_flow.BootstrapFlowTests("runTest")
        self.flow.setUp()
        self.addCleanup(self._cleanup_flow)
        self.profile_names = tuple(
            source.name for source in self.flow.manifest.profiles
        )
        self.profile_declarations = tuple(
            (source.name, source.source, source.ref)
            for source in self.flow.manifest.profiles
        )
        production = bootstrap_flow.load_manifest(bootstrap_flow.PRODUCTION_MANIFEST)
        self.assertEqual(len(production.profiles), 4)
        self.assertEqual(
            self.profile_declarations,
            tuple(
                (source.name, source.source, source.ref)
                for source in production.profiles
            ),
        )
        self.assertEqual(self.profile_names, bootstrap_flow.PROFILE_NAMES)
        self._install_profile_fixtures()
        with bootstrap_flow.app.EngineLock.acquire(
            self.flow.data_root
        ) as engine_lock:
            engine_lock.require_held()
        nancy = next(source for source in self.flow.manifest.profiles if source.name == "nancy")
        nancy_manifest = profile_distribution.read_manifest(nancy.target)
        self.assertIsNotNone(nancy_manifest)
        assert nancy_manifest is not None
        self.assertIn("assets", nancy_manifest.distribution_owned)

    def _cleanup_flow(self) -> None:
        try:
            if hasattr(self, "flow"):
                for remote in self.flow.source_remotes.values():
                    bootstrap_flow.run_git(
                        "--git-dir", str(remote), "fsck", "--full", "--strict"
                    )
                for source in self.flow.manifest.profiles:
                    self.assertFalse(
                        any(path.name == ".git" for path in source.target.rglob("*"))
                    )
                self.flow.tearDown()
        finally:
            if hasattr(self, "flow"):
                self.flow.doCleanups()

    def _install_profile_fixtures(self) -> None:
        for source in self.flow.manifest.profiles:
            remote_files = self._profile_files(
                source, version="0.1.0", marker="remote"
            )
            remote_files.update(
                {
                    ".gitignore": b"*\n",
                    ".github/workflows/distribution.yml": b"name: stale\n",
                    "README.md": b"remote-only readme\n",
                    "scripts/validate_distribution.py": b"raise SystemExit(0)\n",
                    "stale-owned.txt": b"remove me\n",
                    "tests/test_distribution.py": b"def test_stale(): pass\n",
                }
            )
            self._commit_seed(source.name, remote_files, "seed stale profile remote")
            local_files = self._profile_files(
                source, version="0.2.0", marker="local"
            )
            self._write_bytes(source.target, local_files)
            installed = profile_distribution.read_manifest(source.target)
            self.assertIsNotNone(installed)
            assert installed is not None
            installed.source = source.source
            profile_distribution.write_manifest(source.target, installed)
            for directory in (
                "memories",
                "sessions",
                "skills",
                "skins",
                "logs",
                "plans",
                "workspace",
                "cron",
                "home",
            ):
                (source.target / directory).mkdir(exist_ok=True)

    def _profile_files(
        self,
        source: DistributionSource,
        *,
        version: str,
        marker: str,
    ) -> dict[str, bytes]:
        name = source.name
        files = {
            ".no-bundled-skills": b"",
            "SOUL.md": f"{marker} soul for {name}\n".encode("ascii"),
            "config.yaml": bootstrap_flow.source_config(
                "profile", f"{name}-{marker}"
            ).encode("ascii"),
            "slack-manifest.json": json.dumps(
                {"display_name": f"{name}-{marker}"},
                sort_keys=True,
                separators=(",", ":"),
            ).encode("ascii")
            + b"\n",
        }
        rich_fixture_names = {
            self.profile_names[0],
            self.profile_names[1],
            self.profile_names[-1],
        }
        if name in rich_fixture_names:
            files["profile.yaml"] = f"name: {name}-{marker}\n".encode("ascii")
            files[f"assets/{name}-portfolio.png"] = (
                PNG_FIXTURE + f"{name}-{marker}-portfolio".encode("ascii")
            )
            files[f"assets/{name}-slack-avatar.png"] = (
                PNG_FIXTURE + f"{name}-{marker}-avatar".encode("ascii")
            )
        owned = tuple(
            sorted({PurePosixPath(path).parts[0] for path in files})
        )
        return {
            "distribution.yaml": self._profile_manifest(
                name, owned, version
            ).encode("ascii"),
            **files,
        }

    @staticmethod
    def _profile_manifest(
        name: str, owned: tuple[str, ...], version: str
    ) -> str:
        return "\n".join(
            [
                f"name: {name}",
                f"version: {version}",
                "hermes_requires: '>=0.18.2'",
                "distribution_owned:",
                *(f"- {path}" for path in owned),
                "",
            ]
        )

    @staticmethod
    def _write_bytes(root: Path, files: dict[str, bytes]) -> None:
        for relative, content in files.items():
            path = root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
            path.chmod(0o644)

    def _commit_seed(
        self, name: str, files: dict[str, bytes], message: str
    ) -> str:
        seed = self.flow.seeds[name]
        self._write_bytes(seed, files)
        bootstrap_flow.run_git("add", "-f", "-A", cwd=seed)
        bootstrap_flow.run_git("commit", "-m", message, cwd=seed)
        bootstrap_flow.run_git("push", "origin", "main", cwd=seed)
        return bootstrap_flow.run_git("rev-parse", "HEAD", cwd=seed)

    def _remote_head(self, name: str) -> str:
        return bootstrap_flow.run_git(
            "--git-dir",
            str(self.flow.source_remotes[name]),
            "rev-parse",
            "refs/heads/main",
        )

    def _remote_heads(self) -> dict[str, str]:
        return {name: self._remote_head(name) for name in self.profile_names}

    def _snapshot_bytes_modes(
        self, root: Path
    ) -> dict[str, tuple[str, int, bytes | str | None]]:
        return {
            relative: (entry.kind, entry.mode, entry.payload)
            for relative, entry in self.flow._snapshot_tree(root).items()
        }

    def _source(self, name: str) -> DistributionSource:
        return next(
            source
            for source in self.flow.manifest.profiles
            if source.name == name
        )

    def _write_local_revision(self, name: str, revision: int) -> None:
        source = self._source(name)
        self._write_bytes(
            source.target,
            self._profile_files(
                source,
                version=f"0.{revision}.0",
                marker=f"local-{revision}",
            ),
        )

    def _advance_remote(self, name: str, marker: str) -> str:
        seed = self.flow.seeds[name]
        bootstrap_flow.run_git("fetch", "origin", "main", cwd=seed)
        bootstrap_flow.run_git("reset", "--hard", "origin/main", cwd=seed)
        self._write_bytes(
            seed,
            {f"race-{marker}.txt": f"race {marker}\n".encode("ascii")},
        )
        bootstrap_flow.run_git("add", "-f", "-A", cwd=seed)
        bootstrap_flow.run_git("commit", "-m", f"race {marker}", cwd=seed)
        bootstrap_flow.run_git("push", "origin", "main", cwd=seed)
        return bootstrap_flow.run_git("rev-parse", "HEAD", cwd=seed)

    def _run_sync(
        self, *, dry_run: bool = False
    ) -> tuple[int, dict[str, object], str, str]:
        stdout = io.StringIO()
        stderr = io.StringIO()
        arguments = [
            "sync-profiles",
            "--manifest",
            str(bootstrap_flow.PRODUCTION_MANIFEST),
        ]
        if dry_run:
            arguments.append("--dry-run")
        with self.flow._patched_runtime():
            exit_code = cli.main(
                arguments,
                stdout=stdout,
                stderr=stderr,
                environ={"GH_TOKEN": bootstrap_flow.FIXTURE_TOKEN},
            )
        output = stdout.getvalue()
        payload = json.loads(output) if output else {}
        return exit_code, payload, output, stderr.getvalue()

    def _expected_owned_files(self, target: Path) -> tuple[str, ...]:
        installed = profile_distribution.read_manifest(target)
        self.assertIsNotNone(installed)
        assert installed is not None
        files: set[str] = set()
        for raw in installed.distribution_owned:
            owned = PurePosixPath(raw)
            path = target.joinpath(*owned.parts)
            if path.is_file():
                files.add(owned.as_posix())
            else:
                self.assertTrue(path.is_dir(), f"missing owned path {owned}")
                files.update(
                    child.relative_to(target).as_posix()
                    for child in path.rglob("*")
                    if child.is_file()
                )
        return tuple(sorted(files))

    @staticmethod
    def _git_object_id(kind: str, content: bytes) -> str:
        return hashlib.sha1(
            f"{kind} {len(content)}\0".encode("ascii") + content
        ).hexdigest()

    def _expected_gitignore(self, target: Path) -> bytes:
        installed = profile_distribution.read_manifest(target)
        self.assertIsNotNone(installed)
        assert installed is not None
        rules = ["/*", "!/.gitignore", "!/distribution.yaml"]
        seen = set(rules)

        def add(rule: str) -> None:
            if rule not in seen:
                seen.add(rule)
                rules.append(rule)

        for raw in installed.distribution_owned:
            owned = PurePosixPath(raw)
            for depth in range(1, len(owned.parts)):
                add(f"!/{'/'.join(owned.parts[:depth])}/")
            logical = owned.as_posix()
            if target.joinpath(*owned.parts).is_dir():
                add(f"!/{logical}/")
                add(f"!/{logical}/**")
            else:
                add(f"!/{logical}")
        return ("\n".join(rules) + "\n").encode("ascii")

    def _expected_remote_blobs(
        self, target: Path
    ) -> dict[str, tuple[int, bytes]]:
        expected = {
            ".gitignore": (0o100644, self._expected_gitignore(target)),
            "distribution.yaml": (
                0o100644,
                profile_snapshot._canonical_manifest(
                    yaml.safe_load(
                        (target / "distribution.yaml").read_text(
                            encoding="ascii"
                        )
                    ),
                    profile_snapshot._normalize_owned(
                        list(
                            profile_distribution.read_manifest(
                                target
                            ).distribution_owned
                        )
                    ),
                ),
            ),
        }
        for relative in self._expected_owned_files(target):
            local = target / relative
            expected[relative] = (
                stat.S_IFREG | stat.S_IMODE(local.stat().st_mode),
                local.read_bytes(),
            )
        return expected

    def _expected_tree_id(
        self, expected: dict[str, tuple[int, bytes]]
    ) -> str:
        root: dict[str, object] = {}
        for relative, value in expected.items():
            node = root
            parts = PurePosixPath(relative).parts
            for component in parts[:-1]:
                child = node.setdefault(component, {})
                self.assertIsInstance(child, dict)
                assert isinstance(child, dict)
                node = child
            self.assertNotIn(parts[-1], node)
            node[parts[-1]] = value

        def build(node: dict[str, object]) -> str:
            entries: list[tuple[bytes, bytes, str]] = []
            for name, value in node.items():
                encoded_name = name.encode("utf-8")
                if isinstance(value, dict):
                    mode = b"40000"
                    object_id = build(value)
                    sort_key = encoded_name + b"/"
                else:
                    self.assertIsInstance(value, tuple)
                    assert isinstance(value, tuple)
                    file_mode, content = value
                    self.assertIsInstance(file_mode, int)
                    self.assertIsInstance(content, bytes)
                    assert isinstance(file_mode, int)
                    assert isinstance(content, bytes)
                    mode = f"{file_mode:o}".encode("ascii")
                    object_id = self._git_object_id("blob", content)
                    sort_key = encoded_name
                record = (
                    mode
                    + b" "
                    + encoded_name
                    + b"\0"
                    + bytes.fromhex(object_id)
                )
                entries.append((sort_key, record, object_id))
            payload = b"".join(
                record for _key, record, _oid in sorted(entries)
            )
            return self._git_object_id("tree", payload)

        return build(root)

    def _remote_blob_bytes(self, remote: Path, object_id: str) -> bytes:
        environment = bootstrap_flow._minimal_environment(
            Path("/nonexistent"),
            GIT_CONFIG_GLOBAL="/dev/null",
            GIT_CONFIG_NOSYSTEM="1",
            GIT_TERMINAL_PROMPT="0",
        )
        process = bootstrap_flow._REAL_POPEN(
            ("git", "--git-dir", str(remote), "cat-file", "blob", object_id),
            env=environment,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            close_fds=True,
            start_new_session=True,
        )
        bootstrap_flow._CHILD_PROCESSES.append(process)
        try:
            stdout, stderr = process.communicate(
                timeout=bootstrap_flow.PROCESS_TIMEOUT_SECONDS
            )
        except subprocess.TimeoutExpired:
            bootstrap_flow._stop_process(process)
            self.fail("git cat-file exceeded its timeout")
        finally:
            bootstrap_flow._stop_process(process)
        self.assertEqual(process.returncode, 0, stderr.decode("utf-8", "replace"))
        return stdout

    def _assert_exception_graph_hides(
        self, error: BaseException, *markers: str
    ) -> None:
        pending: list[object] = [error]
        visited: set[int] = set()
        while pending:
            value = pending.pop()
            if value is None or id(value) in visited:
                continue
            visited.add(id(value))
            if isinstance(value, str):
                for marker in markers:
                    self.assertNotIn(marker, value)
            elif isinstance(value, bytes):
                for marker in markers:
                    self.assertNotIn(marker.encode("utf-8"), value)
            elif isinstance(value, BaseException):
                pending.extend(
                    (
                        value.args,
                        value.__notes__ if hasattr(value, "__notes__") else (),
                        value.__cause__,
                        value.__context__,
                        value.__traceback__,
                    )
                )
                if isinstance(value, BaseExceptionGroup):
                    pending.append(value.message)
                    pending.extend(value.exceptions)
            elif isinstance(value, TracebackType):
                pending.extend((value.tb_frame, value.tb_next))
            elif isinstance(value, FrameType):
                if "hermes_bootstrap" in value.f_code.co_filename:
                    pending.extend(value.f_locals.values())
            elif isinstance(value, dict):
                pending.extend((*value.keys(), *value.values()))
            elif isinstance(value, (list, tuple, set, frozenset)):
                pending.extend(value)

    def _assert_exact_remote(self, name: str) -> None:
        target = next(
            source.target
            for source in self.flow.manifest.profiles
            if source.name == name
        )
        expected = self._expected_remote_blobs(target)
        remote = self.flow.source_remotes[name]
        observed: dict[str, tuple[int, str]] = {}
        for line in bootstrap_flow.run_git(
            "--git-dir",
            str(remote),
            "ls-tree",
            "-r",
            "refs/heads/main",
        ).splitlines():
            metadata, path = line.split("\t", 1)
            mode, kind, object_id = metadata.split()
            self.assertEqual(kind, "blob")
            observed[path] = (int(mode, 8), object_id)
        self.assertEqual(tuple(sorted(observed)), tuple(sorted(expected)))

        for relative, (expected_mode, expected_bytes) in expected.items():
            with self.subTest(profile=name, path=relative):
                observed_mode, observed_blob = observed[relative]
                self.assertEqual(observed_mode, expected_mode)
                expected_blob = self._git_object_id("blob", expected_bytes)
                self.assertEqual(observed_blob, expected_blob)
                self.assertEqual(
                    self._remote_blob_bytes(remote, observed_blob),
                    expected_bytes,
                )

        self.assertEqual(
            bootstrap_flow.run_git(
                "--git-dir",
                str(remote),
                "rev-parse",
                "refs/heads/main^{tree}",
            ),
            self._expected_tree_id(expected),
        )

        installed = profile_distribution.read_manifest(target)
        assert installed is not None
        declared_assets = tuple(
            PurePosixPath(path)
            for path in installed.distribution_owned
            if PurePosixPath(path).parts[0] == "assets"
        )
        if declared_assets:
            pngs = tuple(
                path
                for path in (target / "assets").rglob("*.png")
                if path.is_file()
            )
            self.assertGreaterEqual(len(pngs), 2)
            for png in pngs:
                content = png.read_bytes()
                self.assertIn(b"\x00", content)
                self.assertTrue(content.startswith(b"\x89PNG\r\n\x1a\n"))

    def test_cli_syncs_every_manifest_profile_exactly_and_is_idempotent(
        self,
    ) -> None:
        remote_before = self._remote_heads()
        local_before = {
            source.name: self.flow._snapshot_tree(source.target)
            for source in self.flow.manifest.profiles
        }

        exit_code, payload, stdout, stderr = self._run_sync()

        self.assertEqual(exit_code, 0)
        self.assertEqual(stderr, "")
        self.assertNotIn(bootstrap_flow.FIXTURE_TOKEN, stdout)
        profiles = payload["profiles"]
        self.assertIsInstance(profiles, list)
        assert isinstance(profiles, list)
        self.assertEqual(
            [item["name"] for item in profiles], list(self.profile_names)
        )
        self.assertEqual(
            [item["status"] for item in profiles],
            ["changed"] * len(self.profile_names),
        )
        first_heads = self._remote_heads()
        for source in self.flow.manifest.profiles:
            with self.subTest(profile=source.name):
                self.assertNotEqual(first_heads[source.name], remote_before[source.name])
                self.assertEqual(
                    self.flow._snapshot_tree(source.target),
                    local_before[source.name],
                )
                self._assert_exact_remote(source.name)

        second_code, second_payload, second_stdout, second_stderr = self._run_sync()

        self.assertEqual(second_code, 0)
        self.assertEqual(second_stderr, "")
        self.assertNotIn(bootstrap_flow.FIXTURE_TOKEN, second_stdout)
        second_profiles = second_payload["profiles"]
        self.assertIsInstance(second_profiles, list)
        assert isinstance(second_profiles, list)
        self.assertEqual(
            [item["status"] for item in second_profiles],
            ["unchanged"] * len(self.profile_names),
        )
        self.assertEqual(self._remote_heads(), first_heads)
        self.assertEqual(
            {item["name"]: item["commit"] for item in second_profiles},
            first_heads,
        )

    def test_dry_run_reports_every_change_without_moving_remote_refs(
        self,
    ) -> None:
        remote_before = self._remote_heads()
        local_before = {
            source.name: self.flow._snapshot_tree(source.target)
            for source in self.flow.manifest.profiles
        }

        exit_code, payload, stdout, stderr = self._run_sync(dry_run=True)

        self.assertEqual(exit_code, 0)
        self.assertEqual(stderr, "")
        self.assertNotIn(bootstrap_flow.FIXTURE_TOKEN, stdout)
        self.assertTrue(payload["dry_run"])
        profiles = payload["profiles"]
        self.assertIsInstance(profiles, list)
        assert isinstance(profiles, list)
        self.assertEqual(
            [item["name"] for item in profiles], list(self.profile_names)
        )
        self.assertEqual(
            [item["status"] for item in profiles],
            ["changed"] * len(self.profile_names),
        )
        self.assertEqual(
            {item["name"]: item["commit"] for item in profiles},
            remote_before,
        )
        self.assertEqual(self._remote_heads(), remote_before)
        for source in self.flow.manifest.profiles:
            self.assertEqual(
                self.flow._snapshot_tree(source.target),
                local_before[source.name],
            )

    def test_invalid_profile_preflight_keeps_every_remote_ref_fixed(self) -> None:
        invalid_name = self.profile_names[len(self.profile_names) // 2]
        invalid_source = self._source(invalid_name)
        manifest_path = invalid_source.target / "distribution.yaml"
        manifest_path.write_text(
            manifest_path.read_text(encoding="ascii") + "- .env\n",
            encoding="ascii",
        )
        remote_before = self._remote_heads()
        local_before = self.flow._snapshot_tree(self.flow.data_root)

        exit_code, payload, stdout, stderr = self._run_sync()

        self.assertEqual(exit_code, 4)
        self.assertEqual(stderr, "")
        self.assertNotIn(bootstrap_flow.FIXTURE_TOKEN, stdout)
        profiles = payload["profiles"]
        self.assertIsInstance(profiles, list)
        assert isinstance(profiles, list)
        self.assertEqual(
            [item["name"] for item in profiles], list(self.profile_names)
        )
        self.assertTrue(all(item["status"] == "failed" for item in profiles))
        self.assertEqual(
            next(
                item["category"]
                for item in profiles
                if item["name"] == invalid_name
            ),
            "invalid_local_profile",
        )
        self.assertEqual(self._remote_heads(), remote_before)
        self.assertEqual(
            self.flow._snapshot_tree(self.flow.data_root), local_before
        )

    def test_empty_owned_directory_blocks_all_apply_side_effects(self) -> None:
        invalid_name = self.profile_names[len(self.profile_names) // 2]
        invalid_source = self._source(invalid_name)
        empty_owned = invalid_source.target / "empty-owned"
        empty_owned.mkdir()
        manifest_path = invalid_source.target / "distribution.yaml"
        manifest_payload = yaml.safe_load(
            manifest_path.read_text(encoding="ascii")
        )
        manifest_payload["distribution_owned"].append("empty-owned")
        manifest_path.write_text(
            yaml.safe_dump(manifest_payload, sort_keys=False),
            encoding="ascii",
        )
        remote_before = self._remote_heads()
        local_before = self.flow._snapshot_tree(self.flow.data_root)

        with (
            mock.patch.object(
                profile_sync,
                "_push_commit",
                wraps=profile_sync._push_commit,
            ) as push,
            mock.patch.object(
                bootstrap_flow.app,
                "synchronize_remote",
                wraps=bootstrap_flow.app.synchronize_remote,
            ) as synchronize_remote,
            mock.patch.object(
                bootstrap_flow.app.Transaction,
                "begin",
                wraps=bootstrap_flow.app.Transaction.begin,
            ) as transaction_begin,
            self.assertRaises(RepositoryError) as raised,
        ):
            self.flow._apply()

        report = raised.exception.profile_sync_report
        self.assertEqual(report.exit_code, 4)
        invalid = next(
            item for item in report.profiles if item.name == invalid_name
        )
        self.assertEqual(invalid.category, "empty_owned_directory")
        self.assertEqual(invalid.message, "local profile snapshot is invalid")
        push.assert_not_called()
        synchronize_remote.assert_not_called()
        transaction_begin.assert_not_called()
        self.assertEqual(self._remote_heads(), remote_before)
        self.assertEqual(
            self.flow._snapshot_tree(self.flow.data_root),
            local_before,
        )
        self.flow._assert_no_temporary_resources()

    def test_push_failure_attempts_later_profiles_and_retry_converges(
        self,
    ) -> None:
        failed_name = self.profile_names[1]
        real_push = profile_sync._push_commit
        attempted: list[str] = []
        local_before = {
            source.name: self.flow._snapshot_tree(source.target)
            for source in self.flow.manifest.profiles
        }

        def fail_one(snapshot, commit, repository, environment):
            attempted.append(snapshot.declaration.name)
            if snapshot.declaration.name == failed_name:
                raise profile_sync._PushRejected
            return real_push(snapshot, commit, repository, environment)

        with mock.patch.object(
            profile_sync, "_push_commit", side_effect=fail_one
        ):
            exit_code, payload, stdout, stderr = self._run_sync()

        self.assertEqual(exit_code, 4)
        self.assertEqual(stderr, "")
        self.assertNotIn(bootstrap_flow.FIXTURE_TOKEN, stdout)
        self.assertEqual(attempted, list(self.profile_names))
        profiles = payload["profiles"]
        assert isinstance(profiles, list)
        self.assertEqual(
            [item["status"] for item in profiles],
            [
                "failed" if name == failed_name else "changed"
                for name in self.profile_names
            ],
        )
        for source in self.flow.manifest.profiles:
            self.assertEqual(
                self.flow._snapshot_tree(source.target),
                local_before[source.name],
            )

        retry_code, retry_payload, retry_stdout, retry_stderr = self._run_sync()

        self.assertEqual(retry_code, 0)
        self.assertEqual(retry_stderr, "")
        self.assertNotIn(bootstrap_flow.FIXTURE_TOKEN, retry_stdout)
        retry_profiles = retry_payload["profiles"]
        assert isinstance(retry_profiles, list)
        self.assertEqual(
            [item["status"] for item in retry_profiles],
            [
                "changed" if name == failed_name else "unchanged"
                for name in self.profile_names
            ],
        )
        for name in self.profile_names:
            self._assert_exact_remote(name)

    def test_one_race_retries_once_and_a_second_race_returns_exit_four(
        self,
    ) -> None:
        initial_code, _payload, _stdout, _stderr = self._run_sync()
        self.assertEqual(initial_code, 0)
        race_name = self.profile_names[0]
        race_remote = self._source(race_name).source
        self._write_local_revision(race_name, 3)
        real_run = profile_sync._run_git_bytes
        push_calls = 0

        def race_once(arguments, cwd, environment, *, max_output_bytes):
            nonlocal push_calls
            output = real_run(
                arguments,
                cwd,
                environment,
                max_output_bytes=max_output_bytes,
            )
            if (
                arguments
                and arguments[0] == "push"
                and arguments[3] == race_remote
                and output is not None
            ):
                push_calls += 1
                if push_calls == 1:
                    self._advance_remote(race_name, "once")
            return output

        with mock.patch.object(
            profile_sync, "_run_git_bytes", side_effect=race_once
        ):
            first_code, first_payload, first_stdout, first_stderr = self._run_sync()

        self.assertEqual(first_code, 0)
        self.assertEqual(first_stderr, "")
        self.assertNotIn(bootstrap_flow.FIXTURE_TOKEN, first_stdout)
        self.assertEqual(push_calls, 2)
        first_profiles = first_payload["profiles"]
        assert isinstance(first_profiles, list)
        self.assertEqual(
            next(
                item["status"]
                for item in first_profiles
                if item["name"] == race_name
            ),
            "changed",
        )
        self._assert_exact_remote(race_name)

        self._write_local_revision(race_name, 4)
        push_calls = 0

        def race_twice(arguments, cwd, environment, *, max_output_bytes):
            nonlocal push_calls
            output = real_run(
                arguments,
                cwd,
                environment,
                max_output_bytes=max_output_bytes,
            )
            if (
                arguments
                and arguments[0] == "push"
                and arguments[3] == race_remote
                and output is not None
            ):
                push_calls += 1
                self._advance_remote(race_name, f"twice-{push_calls}")
            return output

        with mock.patch.object(
            profile_sync, "_run_git_bytes", side_effect=race_twice
        ):
            second_code, second_payload, second_stdout, second_stderr = (
                self._run_sync()
            )

        self.assertEqual(second_code, 4)
        self.assertEqual(second_stderr, "")
        self.assertNotIn(bootstrap_flow.FIXTURE_TOKEN, second_stdout)
        self.assertEqual(push_calls, 2)
        second_profiles = second_payload["profiles"]
        assert isinstance(second_profiles, list)
        failed = next(
            item for item in second_profiles if item["name"] == race_name
        )
        self.assertEqual(failed["status"], "failed")
        self.assertEqual(failed["category"], "push_race_exhausted")

        retry_code, retry_payload, _retry_stdout, retry_stderr = self._run_sync()
        self.assertEqual(retry_code, 0)
        self.assertEqual(retry_stderr, "")
        retry_profiles = retry_payload["profiles"]
        assert isinstance(retry_profiles, list)
        self.assertEqual(
            next(
                item["status"]
                for item in retry_profiles
                if item["name"] == race_name
            ),
            "changed",
        )
        self._assert_exact_remote(race_name)

    def test_missing_profile_bootstrap_uses_remote_distribution_path(
        self,
    ) -> None:
        initial = self.flow._apply()
        self.assertEqual(initial["status"], "applied")
        missing = self.flow.manifest.profiles[-1]
        missing_before = profile_distribution.read_manifest(missing.target)
        self.assertIsNotNone(missing_before)
        assert missing_before is not None
        existing = self.flow.manifest.profiles[:-1]
        remote_before = self._remote_heads()
        existing_before = {
            source.name: self._snapshot_bytes_modes(source.target)
            for source in existing
        }
        shutil.rmtree(missing.target)
        for source in existing:
            self.assertTrue((source.target / "distribution.yaml").is_file())

        result = self.flow._apply()

        self.assertEqual(result["status"], "applied")
        profile_summary = result["profile_sync"]
        self.assertIsInstance(profile_summary, dict)
        assert isinstance(profile_summary, dict)
        self.assertEqual(profile_summary[missing.name], "installed")
        self.assertTrue(
            all(
                profile_summary[source.name] == "unchanged"
                for source in existing
            )
        )
        self.assertEqual(
            self._remote_head(missing.name),
            remote_before[missing.name],
            "missing profile install must seed from remote without publishing",
        )
        for source in existing:
            with self.subTest(existing_profile=source.name):
                self.assertEqual(
                    self._snapshot_bytes_modes(source.target),
                    existing_before[source.name],
                )
        installed = profile_distribution.read_manifest(missing.target)
        self.assertIsNotNone(installed)
        assert installed is not None
        self.assertEqual(installed.name, missing.name)
        self.assertEqual(installed.source, missing.source)
        self.assertEqual(installed.version, missing_before.version)
        self.assertFalse((missing.target / ".git").exists())
        owned_files = self._expected_owned_files(missing.target)
        self.assertTrue(owned_files)
        if "assets" in installed.distribution_owned:
            self.assertTrue(
                all(
                    path.read_bytes().startswith(b"\x89PNG\r\n\x1a\n")
                    for path in (missing.target / "assets").glob("*.png")
                )
            )

    def test_apply_stages_each_existing_profile_at_its_reported_commit(
        self,
    ) -> None:
        real_synchronize = (
            bootstrap_flow.app.profile_sync.synchronize_prepared_profiles
        )
        advance_name = self.profile_names[0]
        captured_reports: list[profile_sync.ProfileSyncReport] = []
        advanced_heads: list[str] = []

        def synchronize_then_advance(prepared, auth, *, dry_run):
            report = real_synchronize(prepared, auth, dry_run=dry_run)
            captured_reports.append(report)
            advanced_heads.append(
                self._advance_remote(advance_name, "after-real-sync-report")
            )
            return report

        with mock.patch.object(
            bootstrap_flow.app.profile_sync,
            "synchronize_prepared_profiles",
            side_effect=synchronize_then_advance,
        ):
            result = self.flow._apply()

        profile_summary = result["profile_sync"]
        self.assertIsInstance(profile_summary, dict)
        assert isinstance(profile_summary, dict)
        self.assertEqual(
            profile_summary,
            {name: "changed" for name in self.profile_names},
        )
        self.assertEqual(len(captured_reports), 1)
        self.assertEqual(len(advanced_heads), 1)
        report = captured_reports[0]
        self.assertIsInstance(report, profile_sync.ProfileSyncReport)
        reported_commits = {
            item.name: item.commit
            for item in report.profiles
        }
        self.assertTrue(all(reported_commits.values()))
        self.assertEqual(
            [
                name
                for name, _source, _ref, _staged_commit, _head
                in self.flow.profile_stage_refs
            ],
            list(self.profile_names),
        )
        for (
            name,
            source,
            ref,
            staged_commit,
            remote_head,
        ) in self.flow.profile_stage_refs:
            with self.subTest(profile=name):
                self.assertEqual(source, self._source(name).source)
                self.assertEqual(ref, reported_commits[name])
                self.assertEqual(staged_commit, reported_commits[name])
                if name == advance_name:
                    self.assertEqual(remote_head, advanced_heads[0])
                    self.assertEqual(self._remote_head(name), advanced_heads[0])
                    self.assertNotEqual(remote_head, reported_commits[name])
                else:
                    self.assertEqual(remote_head, reported_commits[name])
                    self.assertEqual(self._remote_head(name), reported_commits[name])
                self.assertRegex(ref, r"\A[0-9a-f]{40}(?:[0-9a-f]{24})?\Z")
        visible_arguments = {
            argument
            for command in self.flow.child_arguments
            for argument in command
        }
        for source in self.flow.manifest.profiles:
            self.assertIn(source.source, visible_arguments)
        for remote in self.flow.source_remotes.values():
            self.assertNotIn(str(remote), visible_arguments)

    def test_existing_profile_chrome_validation_fails_after_publication_before_local_mutation(
        self,
    ) -> None:
        invalid_name = self.profile_names[0]
        invalid_source = self._source(invalid_name)
        config_path = invalid_source.target / "config.yaml"
        config_path.write_text(
            bootstrap_flow.source_config(
                "profile", f"{invalid_name}-invalid-chrome"
            ).replace(
                "    connect_timeout: 120\n",
                "    connect_timeout: 120.0\n",
            ),
            encoding="ascii",
        )
        remote_before = self._remote_head(invalid_name)
        local_before = self._snapshot_bytes_modes(invalid_source.target)

        with (
            mock.patch.object(
                bootstrap_flow.app,
                "synchronize_remote",
                wraps=bootstrap_flow.app.synchronize_remote,
            ) as synchronize_remote,
            mock.patch.object(
                bootstrap_flow.app.Transaction,
                "begin",
                wraps=bootstrap_flow.app.Transaction.begin,
            ) as transaction_begin,
            self.assertRaises(ValidationError) as raised,
        ):
            self.flow._apply()

        report = raised.exception.profile_sync_report
        self.assertEqual(report.exit_code, 0)
        published = next(
            item for item in report.profiles if item.name == invalid_name
        )
        self.assertEqual(published.status, "changed")
        self.assertEqual(published.category, "published")
        self.assertIsNotNone(published.commit)
        self.assertNotEqual(published.commit, remote_before)
        self.assertEqual(self._remote_head(invalid_name), published.commit)
        self._assert_exact_remote(invalid_name)
        synchronize_remote.assert_not_called()
        transaction_begin.assert_not_called()
        self.assertEqual(
            self._snapshot_bytes_modes(invalid_source.target),
            local_before,
        )
        self.flow._assert_no_temporary_resources()

    def test_late_existing_profile_drift_after_publication_preserves_local_bytes_and_skips_transaction(
        self,
    ) -> None:
        source = self._source(self.profile_names[0])
        config = source.target / "config.yaml"
        remote_before = self._remote_head(source.name)
        real_synchronize = (
            bootstrap_flow.app.profile_sync.synchronize_prepared_profiles
        )
        expected_after: dict[
            str, tuple[str, int, bytes | str | None]
        ] | None = None

        def synchronize_then_mutate(prepared, auth, *, dry_run):
            nonlocal expected_after
            report = real_synchronize(prepared, auth, dry_run=dry_run)
            config.write_bytes(b"late-local-authority\n")
            config.chmod(0o600)
            expected_after = self._snapshot_bytes_modes(source.target)
            return report

        with (
            mock.patch.object(
                bootstrap_flow.app.profile_sync,
                "synchronize_prepared_profiles",
                side_effect=synchronize_then_mutate,
            ),
            mock.patch.object(
                bootstrap_flow.app.Transaction,
                "begin",
                wraps=bootstrap_flow.app.Transaction.begin,
            ) as transaction_begin,
            mock.patch.object(
                bootstrap_flow.app,
                "apply_profile_distribution",
                wraps=bootstrap_flow.app.apply_profile_distribution,
            ) as apply_profile,
            self.assertRaises(RepositoryError) as raised,
        ):
            self.flow._apply()

        self.assertIsNotNone(expected_after)
        self.assertNotEqual(self._remote_head(source.name), remote_before)
        transaction_begin.assert_not_called()
        apply_profile.assert_not_called()
        self.assertEqual(
            self._snapshot_bytes_modes(source.target),
            expected_after,
        )
        self.assertEqual(
            str(raised.exception),
            "profile snapshot rejected (local_profile_changed)",
        )
        failure = next(
            item
            for item in raised.exception.profile_sync_report.profiles
            if item.name == source.name
        )
        self.assertEqual(failure.category, "local_profile_changed")
        self.flow._assert_no_temporary_resources()

    def test_profile_created_after_revalidation_survives_no_overwrite_failure(
        self,
    ) -> None:
        self.assertEqual(self.flow._apply()["status"], "applied")
        missing = self.flow.manifest.profiles[-1]
        shutil.rmtree(missing.target)
        created_after: dict[
            str, tuple[str, int, bytes | str | None]
        ] | None = None
        real_apply_root = bootstrap_flow.app.apply_root_distribution

        def apply_root_then_create(stage, data_root, tx):
            nonlocal created_after
            result = real_apply_root(stage, data_root, tx)
            self._write_bytes(
                missing.target,
                self._profile_files(
                    missing,
                    version="9.9.9",
                    marker="late-local",
                ),
            )
            (missing.target / "config.yaml").chmod(0o600)
            created_after = self._snapshot_bytes_modes(missing.target)
            return result

        with (
            mock.patch.object(
                bootstrap_flow.app,
                "revalidate_profile_snapshots",
                wraps=bootstrap_flow.app.revalidate_profile_snapshots,
            ) as revalidate,
            mock.patch.object(
                bootstrap_flow.app,
                "apply_root_distribution",
                side_effect=apply_root_then_create,
            ),
            mock.patch.object(
                bootstrap_flow.app.Transaction,
                "begin",
                wraps=bootstrap_flow.app.Transaction.begin,
            ) as transaction_begin,
            mock.patch(
                "hermes_bootstrap.distributions.profile_distribution.install_distribution"
            ) as install,
            self.assertRaises(ApplyError) as raised,
        ):
            self.flow._apply()

        self.assertEqual(revalidate.call_count, 1)
        self.assertEqual(transaction_begin.call_count, 1)
        install.assert_not_called()
        self.assertIsNotNone(created_after)
        self.assertEqual(
            self._snapshot_bytes_modes(missing.target),
            created_after,
        )
        self.assertEqual(
            str(raised.exception),
            "could not apply the named profile distribution",
        )
        self.flow._assert_no_temporary_resources()

    def test_existing_invalid_profile_blocks_apply_and_preserves_runtime(
        self,
    ) -> None:
        invalid_name = self.profile_names[-1]
        invalid_source = self._source(invalid_name)
        manifest_path = invalid_source.target / "distribution.yaml"
        manifest_path.write_text(
            manifest_path.read_text(encoding="ascii") + "- .env\n",
            encoding="ascii",
        )
        remote_before = self._remote_heads()
        runtime_before = self.flow._snapshot_tree(self.flow.data_root)
        journals = self.flow.data_root / ".bootstrap" / "transactions"
        journals_before = self.flow._snapshot_tree(journals)

        with self.assertRaises(RepositoryError) as raised:
            self.flow._apply()

        self._assert_exception_graph_hides(
            raised.exception,
            bootstrap_flow.FIXTURE_TOKEN,
            bootstrap_flow.HOST_SECRET_VALUE,
        )
        self.assertEqual(self._remote_heads(), remote_before)
        self.assertEqual(
            self.flow._snapshot_tree(self.flow.data_root), runtime_before
        )
        self.assertEqual(self.flow._snapshot_tree(journals), journals_before)

    def test_apply_sync_failure_preserves_runtime_and_transaction_journals(
        self,
    ) -> None:
        failed_name = self.profile_names[1]
        real_push = profile_sync._push_commit
        remote_before = self._remote_heads()
        runtime_before = self.flow._snapshot_tree(self.flow.data_root)
        journals = self.flow.data_root / ".bootstrap" / "transactions"
        journals_before = self.flow._snapshot_tree(journals)

        def fail_one(snapshot, commit, repository, environment):
            if snapshot.declaration.name == failed_name:
                raise profile_sync._PushRejected
            return real_push(snapshot, commit, repository, environment)

        with (
            mock.patch.object(
                profile_sync, "_push_commit", side_effect=fail_one
            ),
            self.assertRaises(RepositoryError) as raised,
        ):
            self.flow._apply()

        report = raised.exception.profile_sync_report
        self.assertEqual(report.exit_code, 4)
        self.assertEqual(
            next(
                item.category
                for item in report.profiles
                if item.name == failed_name
            ),
            "push_rejected",
        )
        self.assertEqual(
            self.flow._snapshot_tree(self.flow.data_root), runtime_before
        )
        self.assertEqual(self.flow._snapshot_tree(journals), journals_before)
        remote_after = self._remote_heads()
        self.assertEqual(remote_after[failed_name], remote_before[failed_name])
        self.assertTrue(
            all(
                remote_after[name] != remote_before[name]
                for name in self.profile_names
                if name != failed_name
            )
        )
        self._assert_exception_graph_hides(
            raised.exception,
            bootstrap_flow.FIXTURE_TOKEN,
            bootstrap_flow.HOST_SECRET_VALUE,
        )

    def test_secret_markers_are_absent_from_outputs_argv_and_retained_graphs(
        self,
    ) -> None:
        owned_marker = "retained-owned-secret-marker"
        failed_name = self.profile_names[1]
        real_attempt = profile_sync._exact_tree_attempt
        real_scrub = profile_sync._scrub_exception_graph
        retained_sanitized: list[BaseException] = []
        injected = False

        def fail_with_group(snapshot, repository, environment):
            nonlocal injected
            if snapshot.declaration.name == failed_name and not injected:
                injected = True
                child = RuntimeError(
                    bootstrap_flow.FIXTURE_TOKEN,
                    owned_marker.encode("ascii"),
                )
                child.add_note(
                    f"{bootstrap_flow.HOST_SECRET_VALUE} {owned_marker}"
                )
                child.__cause__ = ValueError(
                    f"cause {bootstrap_flow.FIXTURE_TOKEN}"
                )
                child.__context__ = LookupError(
                    f"context {owned_marker}"
                )
                group = ExceptionGroup(
                    f"{bootstrap_flow.FIXTURE_TOKEN} {owned_marker}",
                    [child],
                )
                group.add_note(
                    f"group note {bootstrap_flow.HOST_SECRET_VALUE}"
                )
                raise group
            return real_attempt(snapshot, repository, environment)

        def retain_scrubbed(error: BaseException) -> BaseException:
            scrubbed = real_scrub(error)
            retained_sanitized.append(scrubbed)
            return scrubbed

        ambient_stdout = io.StringIO()
        ambient_stderr = io.StringIO()
        with (
            redirect_stdout(ambient_stdout),
            redirect_stderr(ambient_stderr),
            mock.patch.object(
                profile_sync,
                "_exact_tree_attempt",
                side_effect=fail_with_group,
            ),
            mock.patch.object(
                profile_sync,
                "_scrub_exception_graph",
                side_effect=retain_scrubbed,
            ),
        ):
            exit_code, payload, stdout, stderr = self._run_sync()

        self.assertEqual(exit_code, 4)
        profiles = payload["profiles"]
        assert isinstance(profiles, list)
        self.assertEqual(
            [item["name"] for item in profiles], list(self.profile_names)
        )
        self.assertEqual(
            next(
                item["status"]
                for item in profiles
                if item["name"] == failed_name
            ),
            "failed",
        )
        visible = repr(
            (
                stdout,
                stderr,
                ambient_stdout.getvalue(),
                ambient_stderr.getvalue(),
                self.flow.child_arguments,
            )
        )
        for protected in (
            bootstrap_flow.FIXTURE_TOKEN,
            bootstrap_flow.HOST_SECRET_VALUE,
            owned_marker,
        ):
            self.assertNotIn(protected, visible)
        self.assertTrue(retained_sanitized)
        for sanitized in retained_sanitized:
            self._assert_exception_graph_hides(
                sanitized,
                bootstrap_flow.FIXTURE_TOKEN,
                bootstrap_flow.HOST_SECRET_VALUE,
                owned_marker,
            )
        attempted_names = {
            item["name"]
            for item in profiles
            if item["status"] in {"changed", "unchanged"}
        }
        self.assertTrue(
            set(self.profile_names[self.profile_names.index(failed_name) + 1 :])
            <= attempted_names
        )


if __name__ == "__main__":
    unittest.main()
