"""End-to-end local-first profile publication coverage."""

from __future__ import annotations

import base64
import hashlib
import io
import json
import shutil
import stat
import unittest
from builtins import ExceptionGroup
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path, PurePosixPath
from unittest import mock

from hermes_cli import profile_distribution

try:
    from . import test_bootstrap_flow as bootstrap_flow
except ImportError:
    import test_bootstrap_flow as bootstrap_flow

from hermes_bootstrap import cli, profile_sync
from hermes_bootstrap.errors import RepositoryError
from hermes_bootstrap.models import DistributionSource


PROFILE_OWNED_PATHS = {
    "rick": (
        ".no-bundled-skills",
        "SOUL.md",
        "assets",
        "config.yaml",
        "profile.yaml",
        "slack-manifest.json",
    ),
    "hoffman": (
        ".no-bundled-skills",
        "SOUL.md",
        "assets",
        "config.yaml",
        "profile.yaml",
        "slack-manifest.json",
    ),
    "risarisa": (
        ".no-bundled-skills",
        "SOUL.md",
        "config.yaml",
        "slack-manifest.json",
    ),
    "nancy": (
        ".no-bundled-skills",
        "SOUL.md",
        "assets",
        "config.yaml",
        "profile.yaml",
        "slack-manifest.json",
    ),
}
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
        self.assertEqual(self.profile_names, bootstrap_flow.PROFILE_NAMES)
        self.assertEqual(set(self.profile_names), set(PROFILE_OWNED_PATHS))
        self._install_profile_fixtures()

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
            owned = PROFILE_OWNED_PATHS[source.name]
            remote_files = self._profile_files(
                source.name, owned, version="0.1.0", marker="remote"
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
                source.name, owned, version="0.2.0", marker="local"
            )
            self._write_bytes(source.target, local_files)

    def _profile_files(
        self,
        name: str,
        owned: tuple[str, ...],
        *,
        version: str,
        marker: str,
    ) -> dict[str, bytes]:
        files = {
            "distribution.yaml": self._profile_manifest(
                name, owned, version
            ).encode("ascii"),
            ".no-bundled-skills": b"",
            "SOUL.md": f"{marker} soul for {name}\n".encode("ascii"),
            "config.yaml": f"profile: {name}-{marker}\n".encode("ascii"),
            "profile.yaml": f"name: {name}-{marker}\n".encode("ascii"),
            "slack-manifest.json": json.dumps(
                {"display_name": f"{name}-{marker}"},
                sort_keys=True,
                separators=(",", ":"),
            ).encode("ascii")
            + b"\n",
        }
        if "assets" in owned:
            files[f"assets/{name}-portfolio.png"] = (
                PNG_FIXTURE + f"{name}-{marker}-portfolio".encode("ascii")
            )
            files[f"assets/{name}-slack-avatar.png"] = (
                PNG_FIXTURE + f"{name}-{marker}-avatar".encode("ascii")
            )
        return {
            path: content
            for path, content in files.items()
            if path == "distribution.yaml"
            or path in owned
            or any(path.startswith(f"{item}/") for item in owned)
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

    def _source(self, name: str) -> DistributionSource:
        return next(
            source
            for source in self.flow.manifest.profiles
            if source.name == name
        )

    def _write_local_revision(self, name: str, revision: int) -> None:
        source = self._source(name)
        owned = PROFILE_OWNED_PATHS[name]
        self._write_bytes(
            source.target,
            self._profile_files(
                name,
                owned,
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

    def _assert_exact_remote(self, name: str) -> None:
        target = next(
            source.target
            for source in self.flow.manifest.profiles
            if source.name == name
        )
        owned_files = self._expected_owned_files(target)
        expected = tuple(sorted((".gitignore", "distribution.yaml", *owned_files)))
        remote = self.flow.source_remotes[name]
        observed = tuple(
            bootstrap_flow.run_git(
                "--git-dir",
                str(remote),
                "ls-tree",
                "-r",
                "--name-only",
                "refs/heads/main",
            ).splitlines()
        )
        self.assertEqual(observed, expected)

        mode_by_path: dict[str, int] = {}
        for line in bootstrap_flow.run_git(
            "--git-dir",
            str(remote),
            "ls-tree",
            "-r",
            "refs/heads/main",
        ).splitlines():
            metadata, path = line.split("\t", 1)
            mode_by_path[path] = int(metadata.split()[0], 8)
        self.assertEqual(mode_by_path[".gitignore"], 0o100644)
        self.assertEqual(mode_by_path["distribution.yaml"], 0o100644)
        for relative in owned_files:
            local = target / relative
            self.assertEqual(
                mode_by_path[relative],
                stat.S_IFREG | stat.S_IMODE(local.stat().st_mode),
            )
            expected_blob = hashlib.sha1(
                f"blob {local.stat().st_size}\0".encode("ascii")
                + local.read_bytes()
            ).hexdigest()
            self.assertEqual(
                bootstrap_flow.run_git(
                    "--git-dir",
                    str(remote),
                    "rev-parse",
                    f"refs/heads/main:{relative}",
                ),
                expected_blob,
            )

        manifest = profile_distribution.read_manifest(target)
        assert manifest is not None
        declared_assets = tuple(
            PurePosixPath(path)
            for path in manifest.distribution_owned
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
        race_remote = str(self.flow.source_remotes[race_name])
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
        missing = self.flow.manifest.profiles[-1]
        shutil.rmtree(missing.target)
        for source in self.flow.manifest.profiles[:-1]:
            self.assertTrue((source.target / "distribution.yaml").is_file())

        result = self.flow._apply()

        self.assertEqual(result["status"], "applied")
        profile_summary = result["profile_sync"]
        self.assertIsInstance(profile_summary, dict)
        assert isinstance(profile_summary, dict)
        self.assertEqual(profile_summary[missing.name], "installed")
        self.assertTrue(
            all(
                profile_summary[source.name] == "changed"
                for source in self.flow.manifest.profiles[:-1]
            )
        )
        installed = profile_distribution.read_manifest(missing.target)
        self.assertIsNotNone(installed)
        assert installed is not None
        self.assertEqual(installed.name, missing.name)
        self.assertEqual(installed.source, missing.source)
        self.assertEqual(installed.version, "0.1.0")
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
        result = self.flow._apply()

        profile_summary = result["profile_sync"]
        self.assertIsInstance(profile_summary, dict)
        assert isinstance(profile_summary, dict)
        self.assertEqual(
            profile_summary,
            {name: "changed" for name in self.profile_names},
        )
        self.assertEqual(
            [name for name, _ref, _head in self.flow.profile_stage_refs],
            list(self.profile_names),
        )
        for name, ref, remote_head in self.flow.profile_stage_refs:
            with self.subTest(profile=name):
                self.assertEqual(ref, remote_head)
                self.assertEqual(ref, self._remote_head(name))
                self.assertRegex(ref, r"\A[0-9a-f]{40}(?:[0-9a-f]{24})?\Z")

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

        visible_exception = repr(
            (raised.exception, raised.exception.__dict__)
        )
        self.assertNotIn(bootstrap_flow.FIXTURE_TOKEN, visible_exception)
        self.assertNotIn(bootstrap_flow.HOST_SECRET_VALUE, visible_exception)
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
        visible_exception = repr(
            (raised.exception, raised.exception.__dict__)
        )
        self.assertNotIn(bootstrap_flow.FIXTURE_TOKEN, visible_exception)
        self.assertNotIn(bootstrap_flow.HOST_SECRET_VALUE, visible_exception)

    def test_secret_markers_are_absent_from_outputs_argv_and_retained_graphs(
        self,
    ) -> None:
        owned_marker = "retained-owned-secret-marker"
        failed_name = self.profile_names[1]
        real_attempt = profile_sync._exact_tree_attempt
        real_scrub = profile_sync._scrub_exception_graph
        retained: list[BaseException] = []
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
                raise ExceptionGroup(
                    f"{bootstrap_flow.FIXTURE_TOKEN} {owned_marker}",
                    [child],
                )
            return real_attempt(snapshot, repository, environment)

        def retain_scrubbed(error: BaseException) -> BaseException:
            scrubbed = real_scrub(error)
            retained.append(scrubbed)
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
                retained,
                self.flow.child_arguments,
            )
        )
        for protected in (
            bootstrap_flow.FIXTURE_TOKEN,
            bootstrap_flow.HOST_SECRET_VALUE,
            owned_marker,
        ):
            self.assertNotIn(protected, visible)
        self.assertTrue(retained)
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
