"""End-to-end local-first profile publication coverage."""

from __future__ import annotations

import base64
import io
import json
import shutil
import stat
import subprocess
import unittest
from contextlib import redirect_stderr, redirect_stdout
from dataclasses import replace
from pathlib import Path, PurePosixPath
from unittest import mock

import yaml
from hermes_cli import profile_distribution

try:
    from . import test_bootstrap_flow as bootstrap_flow
except ImportError:
    import test_bootstrap_flow as bootstrap_flow

from hermes_bootstrap import cli, profile_snapshot, profile_sync
from hermes_bootstrap.errors import RepositoryError
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
            commit = self._commit_seed(source.name, remote_files, "seed stale profile remote")
            self.flow.manifest = replace(
                self.flow.manifest,
                profiles=tuple(
                    replace(profile, source_commit=commit)
                    if profile.name == source.name
                    else profile
                    for profile in self.flow.manifest.profiles
                ),
            )
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
        rich_fixture_names = {"rick", "hoffman", "nancy"}
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
            installed_path = (
                PurePosixPath(".env.EXAMPLE")
                if owned == PurePosixPath(".env.template")
                else owned
            )
            path = target.joinpath(*installed_path.parts)
            if path.is_file():
                files.add(owned.as_posix())
            else:
                self.assertTrue(path.is_dir(), f"missing owned path {owned}")
                files.update(
                    (owned / child.relative_to(path)).as_posix()
                    for child in path.rglob("*")
                    if child.is_file()
                )
        return tuple(sorted(files))

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

        owned_paths = profile_snapshot._normalize_owned(
            list(installed.distribution_owned)
        )
        for owned in owned_paths:
            for depth in range(1, len(owned.parts)):
                add(f"!/{'/'.join(owned.parts[:depth])}/")
            logical = owned.as_posix()
            installed_path = (
                target / ".env.EXAMPLE"
                if owned == PurePosixPath(".env.template")
                else target.joinpath(*owned.parts)
            )
            if installed_path.is_dir():
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
            local = (
                target / ".env.EXAMPLE"
                if relative == ".env.template"
                else target / relative
            )
            expected[relative] = (
                stat.S_IFREG | stat.S_IMODE(local.stat().st_mode),
                local.read_bytes(),
            )
        return expected

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
                self.assertEqual(
                    self._remote_blob_bytes(remote, observed_blob),
                    expected_bytes,
                )


    def test_cli_syncs_every_manifest_profile_exactly_and_is_idempotent(
        self,
    ) -> None:
        for source in self.flow.manifest.profiles:
            legacy_env = source.target / ".env"
            legacy_env.write_bytes(b"\xff\x00user-owned environment bytes\n")
            legacy_env.chmod(0o640)
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
                profile_summary[source.name] == "preserved"
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

        with self.assertRaises(RepositoryError) as raised:
            self.flow._apply()

        for protected in (
            bootstrap_flow.FIXTURE_TOKEN,
            bootstrap_flow.HOST_SECRET_VALUE,
        ):
            self.assertNotIn(protected, str(raised.exception))
        self.assertEqual(self._remote_heads(), remote_before)
        self.assertEqual(
            self.flow._snapshot_tree(self.flow.data_root), runtime_before
        )

    def test_secret_markers_are_absent_from_outputs_and_argv(
        self,
    ) -> None:
        owned_marker = "owned-secret-marker"
        failed_name = self.profile_names[1]
        real_attempt = profile_sync._exact_tree_attempt
        attempted: list[str] = []

        def fail_one(snapshot, repository, environment):
            attempted.append(snapshot.declaration.name)
            if snapshot.declaration.name == failed_name:
                raise RuntimeError(
                    f"{bootstrap_flow.FIXTURE_TOKEN} "
                    f"{bootstrap_flow.HOST_SECRET_VALUE} {owned_marker}"
                )
            return real_attempt(snapshot, repository, environment)

        ambient_stdout = io.StringIO()
        ambient_stderr = io.StringIO()
        with (
            redirect_stdout(ambient_stdout),
            redirect_stderr(ambient_stderr),
            mock.patch.object(
                profile_sync,
                "_exact_tree_attempt",
                side_effect=fail_one,
            ),
        ):
            exit_code, payload, stdout, stderr = self._run_sync()

        self.assertEqual(exit_code, 4)
        self.assertEqual(attempted, list(self.profile_names))
        profiles = payload["profiles"]
        assert isinstance(profiles, list)
        self.assertEqual(
            [item["name"] for item in profiles], list(self.profile_names)
        )
        self.assertEqual(
            [item["status"] for item in profiles],
            [
                "failed" if name == failed_name else "changed"
                for name in self.profile_names
            ],
        )
        visible = repr(
            (
                stdout,
                stderr,
                payload,
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


if __name__ == "__main__":
    unittest.main()
