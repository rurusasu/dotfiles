from __future__ import annotations

import errno
import os
import random
import re
import resource
import shutil
import signal
import socket
import stat
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

import yaml


BOOTSTRAP_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BOOTSTRAP_ROOT))

from hermes_bootstrap.models import BootstrapManifest, DistributionSource
from hermes_bootstrap import profile_snapshot
from hermes_bootstrap.profile_snapshot import ProfileSnapshotError, prepare_profile_snapshots


class ProfileSnapshotTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.data_root = self.root / "data"
        self.data_root.mkdir()
        self.scratch = self.root / "scratch"
        self.scratch.mkdir(mode=0o700)

    def profile(self, name: str) -> DistributionSource:
        return DistributionSource(
            name,
            f"https://github.com/rurusasu/hermes-profile-{name}.git",
            "main",
            self.data_root / "profiles" / name,
            "distribution.yaml",
        )

    def manifest(self, *profiles: DistributionSource) -> BootstrapManifest:
        root = DistributionSource(
            "default", "https://github.com/rurusasu/hermes-home.git", "main", self.data_root, "root-distribution.yaml"
        )
        return BootstrapManifest(1, self.data_root, (), root, profiles, ())

    def write_profile(self, name: str, owned: list[str], **overrides: object) -> Path:
        home = self.profile(name).target
        home.mkdir(parents=True, exist_ok=True)
        payload: dict[str, object] = {
            "name": name,
            "version": "0.1.0",
            "hermes_requires": ">=0.18.2",
            "distribution_owned": owned,
        }
        payload.update(overrides)
        (home / "distribution.yaml").write_text(yaml.safe_dump(payload, sort_keys=False), encoding="utf-8")
        return home

    def prepare(self, name: str, *, owned: list[str], **overrides: object):
        home = self.write_profile(name, owned, **overrides)
        for item in owned:
            path = home / item
            if item.endswith("/") or item == "assets" or item.startswith("assets/"):
                path.mkdir(parents=True, exist_ok=True)
                (path / "fixture.txt").write_bytes(b"safe\n")
            elif not path.exists():
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b"safe\n")
        prepared = prepare_profile_snapshots(self.manifest(self.profile(name)), self.scratch, allow_missing=False)
        return prepared.snapshots[0]

    def test_canonical_manifest_strips_runtime_fields_and_rejects_unknown_keys(self) -> None:
        snapshot = self.prepare(
            "rick",
            owned=["SOUL.md", "assets"],
            description="A canonical profile",
            author="Rick Sanchez",
            license="MIT",
            env_requires=[{"name": "RICK_PORTAL", "description": "Portal fluid", "required": False}],
            source="https://example.invalid/ignored.git",
            installed_at="2026-07-23T00:00:00Z",
        )
        payload = yaml.safe_load(snapshot.manifest_bytes)
        self.assertNotIn("source", payload)
        self.assertNotIn("installed_at", payload)
        self.assertEqual(payload["distribution_owned"], ["SOUL.md", "assets"])
        self.assertEqual(tuple(payload), ("name", "version", "description", "hermes_requires", "author", "license", "env_requires", "distribution_owned"))

        home = self.profile("rick").target
        payload["unknown"] = "nope"
        (home / "distribution.yaml").write_text(yaml.safe_dump(payload, sort_keys=False), encoding="utf-8")
        clean_scratch = self.root / "unknown-key"
        clean_scratch.mkdir(mode=0o700)
        with self.assertRaises(ProfileSnapshotError):
            prepare_profile_snapshots(self.manifest(self.profile("rick")), clean_scratch, allow_missing=False)

    def test_gitignore_is_an_exact_root_allowlist_with_nested_parents(self) -> None:
        snapshot = self.prepare("rick", owned=["SOUL.md", "assets/icons"])
        self.assertEqual(
            snapshot.gitignore_bytes.decode("ascii").splitlines(),
            [
                "/*", "!/.gitignore", "!/distribution.yaml", "!/SOUL.md",
                "!/assets/", "!/assets/icons/", "!/assets/icons/**",
            ],
        )

    def test_manifest_rejects_duplicate_identity_empty_overlap_and_nonportable_ownership(self) -> None:
        home = self.write_profile("rick", ["SOUL.md"])
        (home / "SOUL.md").write_text("safe\n", encoding="utf-8")
        invalid = (
            "name: rick\nname: duplicate\nversion: 0.1.0\nhermes_requires: '>=0.18.2'\ndistribution_owned: [SOUL.md]\n",
            yaml.safe_dump({"name": "hoffman", "version": "0.1.0", "hermes_requires": ">=0.18.2", "distribution_owned": ["SOUL.md"]}),
            yaml.safe_dump({"name": "rick", "version": "0.1.0", "hermes_requires": ">=0.18.2", "distribution_owned": []}),
            yaml.safe_dump({"name": "rick", "version": "0.1.0", "hermes_requires": ">=0.18.2", "distribution_owned": ["assets", "assets/icon.png"]}),
            yaml.safe_dump({"name": "rick", "version": "0.1.0", "hermes_requires": ">=0.18.2", "distribution_owned": ["bad:name"]}),
            yaml.safe_dump({"name": "rick", "version": "0.1.0", "hermes_requires": ">=0.18.2", "distribution_owned": [".gitignore"]}),
            yaml.safe_dump({"name": "rick", "version": "0.1.0", "hermes_requires": ">=0.18.2", "distribution_owned": ["distribution.yaml"]}),
        )
        for content in invalid:
            with self.subTest(content=content):
                (home / "distribution.yaml").write_text(content, encoding="utf-8")
                with self.assertRaises(ProfileSnapshotError):
                    prepare_profile_snapshots(self.manifest(self.profile("rick")), self.scratch, allow_missing=False)

    def test_rejects_an_owned_directory_without_publishable_files(self) -> None:
        home = self.write_profile("rick", ["assets"])
        (home / "assets" / "nested-empty").mkdir(parents=True)

        with self.assertRaises(ProfileSnapshotError) as caught:
            prepare_profile_snapshots(
                self.manifest(self.profile("rick")),
                self.scratch,
                allow_missing=False,
            )

        self.assertEqual(caught.exception.profile, "rick")
        self.assertEqual(caught.exception.category, "empty_owned_directory")
        self.assertEqual(
            str(caught.exception),
            "profile snapshot rejected (empty_owned_directory)",
        )
        self.assertEqual(list(self.scratch.iterdir()), [])

    def test_rejects_reserved_paths_and_secret_candidates(self) -> None:
        for unsafe in (
            ".env", "auth.json", ".git/config", "memories", "sessions", "logs",
            "plans", "workspace", "home", "cron/output", "cron/state", "locks",
        ):
            with self.subTest(unsafe=unsafe), self.assertRaises(ProfileSnapshotError):
                self.prepare("rick", owned=[unsafe])

        for index, content in enumerate((
            b"ghp_abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN",
            b"xoxb-valid",
            b"xoxp-valid",
            b"xoxa-valid",
            b"xoxr-valid",
            b"xoxs-valid",
            b"xapp-valid",
            b"-----BEGIN PRIVATE KEY-----",
        )):
            with self.subTest(content=content), self.assertRaises(ProfileSnapshotError):
                home = self.write_profile("rick", ["SOUL.md"])
                (home / "SOUL.md").write_bytes(content)
                scratch = self.root / f"secret-{index}"
                scratch.mkdir(mode=0o700)
                prepare_profile_snapshots(self.manifest(self.profile("rick")), scratch, allow_missing=False)

    def test_rejects_credential_stems_in_every_path_component(self) -> None:
        unsafe_paths = (
            "token.json/payload.txt",
            "credentials.pem/nested/data.txt",
            "secret.txt/archive/payload.txt",
            "secrets.json/payload.txt",
            "token.backup.json/archive/payload.txt",
            "credentials.prod.yaml/nested/data.txt",
            "assets/runtime/cache.bin",
            "assets/cron/state/checkpoint.json",
            "nested/cron/output/latest.log",
        )
        for index, unsafe in enumerate(unsafe_paths):
            with self.subTest(unsafe=unsafe):
                name = f"credential{index}"
                home = self.write_profile(name, [unsafe])
                candidate = home / unsafe
                candidate.parent.mkdir(parents=True)
                candidate.write_text("safe\n", encoding="utf-8")
                scratch = self.root / f"credential-scratch-{index}"
                scratch.mkdir(mode=0o700)

                with self.assertRaises(ProfileSnapshotError) as caught:
                    prepare_profile_snapshots(
                        self.manifest(self.profile(name)), scratch, allow_missing=False
                    )

                self.assertEqual(caught.exception.category, "invalid_local_profile")
                self.assertEqual(list(scratch.iterdir()), [])

        safe_home = self.write_profile(
            "legitimate", ["assets/avatar.png", "portfolio.pdf"]
        )
        (safe_home / "assets").mkdir()
        (safe_home / "assets" / "avatar.png").write_bytes(b"avatar")
        (safe_home / "portfolio.pdf").write_bytes(b"portfolio")
        safe_scratch = self.root / "legitimate-scratch"
        safe_scratch.mkdir(mode=0o700)

        snapshot = prepare_profile_snapshots(
            self.manifest(self.profile("legitimate")), safe_scratch, allow_missing=False
        ).snapshots[0]

        self.assertEqual(
            [entry.path.as_posix() for entry in snapshot.entries],
            ["assets/avatar.png", "portfolio.pdf"],
        )

    def test_rejects_a_secret_crossing_the_streaming_chunk_boundary(self) -> None:
        home = self.write_profile("rick", ["SOUL.md"])
        token = b"ghp_abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN"
        (home / "SOUL.md").write_bytes(b"x" * (64 * 1024 - 5) + b"!" + token)
        scratch = self.root / "boundary-secret"
        scratch.mkdir(mode=0o700)

        with mock.patch.object(profile_snapshot, "_reject_sensitive_bytes", wraps=profile_snapshot._reject_sensitive_bytes) as reject:
            with self.assertRaises(ProfileSnapshotError):
                prepare_profile_snapshots(self.manifest(self.profile("rick")), scratch, allow_missing=False)

        self.assertGreater(reject.call_count, 2)
        self.assertFalse((scratch / "rick").exists())

    def test_rejects_an_xapp_secret_crossing_the_streaming_chunk_boundary(self) -> None:
        home = self.write_profile("rick", ["SOUL.md"])
        token = b"xapp-1234567890-abcdefgh"
        (home / "SOUL.md").write_bytes(b"x" * (64 * 1024 - 3) + b"!" + token)
        scratch = self.root / "xapp-boundary-secret"
        scratch.mkdir(mode=0o700)

        with self.assertRaises(ProfileSnapshotError) as caught:
            prepare_profile_snapshots(self.manifest(self.profile("rick")), scratch, allow_missing=False)

        self.assertEqual(caught.exception.category, "invalid_local_profile")
        self.assertFalse((scratch / "rick").exists())

    def test_rejects_a_short_xoxb_secret_crossing_the_streaming_chunk_boundary(self) -> None:
        home = self.write_profile("rick", ["SOUL.md"])
        token = b"xoxb-valid"
        (home / "SOUL.md").write_bytes(b"x" * (64 * 1024 - 3) + b"!" + token)
        scratch = self.root / "xoxb-boundary-secret"
        scratch.mkdir(mode=0o700)

        with self.assertRaises(ProfileSnapshotError) as caught:
            prepare_profile_snapshots(self.manifest(self.profile("rick")), scratch, allow_missing=False)

        self.assertEqual(caught.exception.category, "invalid_local_profile")
        self.assertFalse((scratch / "rick").exists())

    def test_streaming_secret_match_at_chunk_end_waits_for_lookahead(self) -> None:
        token = b"xoxb-valid"
        prefix = b"a" * (
            profile_snapshot._READ_CHUNK_BYTES - len(token) - 1
        ) + b"!"
        cases = ((b"_", False), (b"!", True), (b"", True))

        for index, (suffix, rejected) in enumerate(cases):
            with self.subTest(suffix=suffix, rejected=rejected):
                name = f"lookahead{index}"
                home = self.write_profile(name, ["SOUL.md"])
                content = prefix + token + suffix
                (home / "SOUL.md").write_bytes(content)
                scratch = self.root / f"lookahead-scratch-{index}"
                scratch.mkdir(mode=0o700)

                if rejected:
                    with self.assertRaises(ProfileSnapshotError) as caught:
                        prepare_profile_snapshots(
                            self.manifest(self.profile(name)),
                            scratch,
                            allow_missing=False,
                        )
                    self.assertEqual(
                        caught.exception.category, "invalid_local_profile"
                    )
                    self.assertEqual(list(scratch.iterdir()), [])
                else:
                    snapshot = prepare_profile_snapshots(
                        self.manifest(self.profile(name)),
                        scratch,
                        allow_missing=False,
                    ).snapshots[0]
                    self.assertEqual((snapshot.root / "SOUL.md").read_bytes(), content)

    def test_rejects_arbitrarily_long_streaming_tokens_at_delimiter_or_eof(self) -> None:
        body = b"a" * (profile_snapshot._READ_CHUNK_BYTES + 300)
        cases = (
            (b"xoxb-", b"!"),
            (b"xoxb-", b""),
            (b"ghp_", b"!"),
            (b"ghp_", b""),
        )

        for index, (prefix, suffix) in enumerate(cases):
            with self.subTest(prefix=prefix, suffix=suffix):
                name = f"longtoken{index}"
                home = self.write_profile(name, ["SOUL.md"])
                (home / "SOUL.md").write_bytes(b"!" + prefix + body + suffix)
                scratch = self.root / f"long-token-{index}"
                scratch.mkdir(mode=0o700)

                with self.assertRaises(ProfileSnapshotError) as caught:
                    prepare_profile_snapshots(
                        self.manifest(self.profile(name)),
                        scratch,
                        allow_missing=False,
                    )

                self.assertEqual(caught.exception.category, "invalid_local_profile")
                self.assertEqual(list(scratch.iterdir()), [])

    def test_accepts_long_token_shapes_with_continuation_or_no_leading_boundary(self) -> None:
        body = b"a" * (profile_snapshot._READ_CHUNK_BYTES + 300)
        forgotten_leading_slack = (
            b"z" * (profile_snapshot._READ_CHUNK_BYTES - 257)
            + b"A"
            + b"xoxb-"
            + body
            + b"!"
        )
        forgotten_leading_github = (
            b"z" * (profile_snapshot._READ_CHUNK_BYTES - 257)
            + b"A"
            + b"ghp_"
            + body
            + b"!"
        )
        cases = (
            b"!xoxb-" + body + b"_!",
            b"!ghp_" + body + b"_!",
            b"Axoxb-" + body + b"!",
            b"Aghp_" + body + b"!",
            forgotten_leading_slack,
            forgotten_leading_github,
        )

        for index, content in enumerate(cases):
            with self.subTest(index=index):
                name = f"longsafe{index}"
                home = self.write_profile(name, ["SOUL.md"])
                (home / "SOUL.md").write_bytes(content)
                scratch = self.root / f"long-safe-{index}"
                scratch.mkdir(mode=0o700)

                snapshot = prepare_profile_snapshots(
                    self.manifest(self.profile(name)),
                    scratch,
                    allow_missing=False,
                ).snapshots[0]

                self.assertEqual((snapshot.root / "SOUL.md").read_bytes(), content)

    def test_rejects_a_private_key_header_crossing_a_chunk_boundary(self) -> None:
        home = self.write_profile("rick", ["SOUL.md"])
        header = b"-----BEGIN OPENSSH PRIVATE KEY-----"
        content = (
            b"x" * (profile_snapshot._READ_CHUNK_BYTES - len(header) // 2)
            + header
        )
        (home / "SOUL.md").write_bytes(content)

        with self.assertRaises(ProfileSnapshotError) as caught:
            prepare_profile_snapshots(
                self.manifest(self.profile("rick")),
                self.scratch,
                allow_missing=False,
            )

        self.assertEqual(caught.exception.category, "invalid_local_profile")
        self.assertEqual(list(self.scratch.iterdir()), [])

    def test_rejects_every_supported_private_key_header_at_every_split(self) -> None:
        headers = (
            b"-----BEGIN PRIVATE KEY-----",
            b"-----BEGIN ENCRYPTED PRIVATE KEY-----",
            b"-----BEGIN RSA PRIVATE KEY-----",
            b"-----BEGIN EC PRIVATE KEY-----",
            b"-----BEGIN DSA PRIVATE KEY-----",
            b"-----BEGIN OPENSSH PRIVATE KEY-----",
        )
        split_cases = 0

        for header in headers:
            for split in range(len(header) + 1):
                scanner = profile_snapshot._SensitiveStreamScanner()
                rejected = False
                try:
                    scanner.feed(b"safe!" + header[:split])
                    scanner.feed(header[split:] + b"!tail")
                    scanner.finish()
                except ValueError:
                    rejected = True
                if not rejected:
                    self.fail(f"private header escaped at split {split}: {header!r}")
                split_cases += 1

        self.assertEqual(split_cases, 197)

    def test_accepts_a_long_bogus_uppercase_private_key_label(self) -> None:
        content = b"-----BEGIN " + b"A" * 4096 + b" PRIVATE KEY-----"

        for width in (len(content), 17):
            scanner = profile_snapshot._SensitiveStreamScanner()
            for start in range(0, len(content), width):
                scanner.feed(content[start : start + width])
            scanner.finish()

    def test_streaming_detector_matches_deterministic_whole_buffer_oracle(self) -> None:
        github_prefixes = (
            b"ghp_",
            b"gho_",
            b"ghu_",
            b"ghs_",
            b"ghr_",
            b"github_pat_",
        )
        slack_prefixes = (
            b"xoxb-",
            b"xoxp-",
            b"xoxa-",
            b"xoxr-",
            b"xoxs-",
            b"xapp-",
        )
        private_headers = (
            b"-----BEGIN PRIVATE KEY-----",
            b"-----BEGIN ENCRYPTED PRIVATE KEY-----",
            b"-----BEGIN RSA PRIVATE KEY-----",
            b"-----BEGIN EC PRIVATE KEY-----",
            b"-----BEGIN DSA PRIVATE KEY-----",
            b"-----BEGIN OPENSSH PRIVATE KEY-----",
        )
        github_oracle = re.compile(
            rb"(?<![A-Za-z0-9_])(?:gh[pousr]_[A-Za-z0-9]{20,}"
            rb"|github_pat_[A-Za-z0-9_]{20,})(?![A-Za-z0-9_])"
        )
        slack_oracle = re.compile(
            rb"(?<![A-Za-z0-9_])(?:xoxb|xoxp|xoxa|xoxr|xoxs|xapp)-"
            rb"[A-Za-z0-9-]+(?![A-Za-z0-9_-])"
        )
        private_oracle = re.compile(
            b"(?:" + b"|".join(re.escape(header) for header in private_headers) + b")"
        )
        corpus: list[bytes] = []

        for prefix in github_prefixes:
            token = prefix + b"A" * 20
            long_token = prefix + b"A" * 600
            corpus.extend(
                (
                    token,
                    b"!" + token + b"!",
                    b"A" + token + b"!",
                    b"!" + prefix + b"A" * 19 + b"!",
                    b"!" + token + b"_!",
                    b"!" + long_token + b"!",
                    b"!" + long_token,
                    b"!" + long_token + b"_!",
                )
            )
        for prefix in slack_prefixes:
            token = prefix + b"valid"
            long_token = prefix + b"a" * 600
            corpus.extend(
                (
                    token,
                    b"!" + token + b"!",
                    b"A" + token + b"!",
                    b"!" + token + b"_!",
                    b"!" + long_token + b"!",
                    b"!" + long_token,
                    b"!" + long_token + b"_!",
                )
            )
        for header in private_headers:
            corpus.extend(
                (
                    header,
                    b"safe!" + header + b"!tail",
                    header.replace(b"PRIVATE", b"PUBLIC"),
                )
            )
        corpus.extend(
            (
                b"",
                b"ordinary profile content",
                b"!ghp_short!",
                b"!xapp-!",
                b"-----BEGIN " + b"A" * 4096 + b" PRIVATE KEY-----",
            )
        )
        random_source = random.Random(20260723)
        alphabet = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_!- "
        for _ in range(512):
            corpus.append(
                bytes(
                    random_source.choice(alphabet)
                    for _ in range(random_source.randrange(0, 321))
                )
            )

        evaluations = 0
        for content in corpus:
            expected = bool(
                github_oracle.search(content)
                or slack_oracle.search(content)
                or private_oracle.search(content)
            )
            widths = (1, 2, 3, 7, 31, 64, 257, max(1, len(content)))
            for width in widths:
                scanner = profile_snapshot._SensitiveStreamScanner()
                actual = False
                try:
                    for start in range(0, len(content), width):
                        scanner.feed(content[start : start + width])
                    scanner.finish()
                except ValueError:
                    actual = True
                if actual != expected:
                    self.fail(
                        "streaming detector disagreed with oracle "
                        f"at width {width}: {content[:120]!r}"
                    )
                evaluations += 1

        self.assertEqual(evaluations, 5000)

    def test_manifest_growth_is_rejected_after_one_bounded_probe(self) -> None:
        home = self.write_profile("rick", ["SOUL.md"])
        (home / "SOUL.md").write_text("safe\n", encoding="utf-8")
        manifest_path = home / "distribution.yaml"
        initial = manifest_path.stat()
        growth = b"# late growth\n"
        original_read = os.read
        bytes_read = 0
        appends = 0

        def read_then_grow(descriptor: int, count: int) -> bytes:
            nonlocal appends, bytes_read
            chunk = original_read(descriptor, count)
            status = os.fstat(descriptor)
            if (status.st_dev, status.st_ino) == (initial.st_dev, initial.st_ino):
                bytes_read += len(chunk)
                if chunk and appends < 4:
                    with manifest_path.open("ab", buffering=0) as handle:
                        handle.write(growth)
                    appends += 1
            return chunk

        started = time.monotonic()
        with mock.patch.object(profile_snapshot.os, "read", side_effect=read_then_grow):
            with self.assertRaises(ProfileSnapshotError) as caught:
                prepare_profile_snapshots(
                    self.manifest(self.profile("rick")),
                    self.scratch,
                    allow_missing=False,
                )

        self.assertGreaterEqual(appends, 1)
        self.assertEqual(bytes_read, initial.st_size + 1)
        self.assertLess(time.monotonic() - started, 1.0)
        self.assertEqual(caught.exception.category, "invalid_local_profile")
        self.assertEqual(list(self.scratch.iterdir()), [])

    def test_owned_file_growth_is_rejected_without_copying_past_captured_size(self) -> None:
        home = self.write_profile("rick", ["SOUL.md"])
        source = home / "SOUL.md"
        content = b"A" * profile_snapshot._READ_CHUNK_BYTES
        source.write_bytes(content)
        original_write = profile_snapshot._write_descriptor
        copied_bytes = 0
        appends = 0

        def write_then_grow(descriptor: int, chunk: bytes) -> None:
            nonlocal appends, copied_bytes
            original_write(descriptor, chunk)
            if chunk == content:
                copied_bytes += len(chunk)
                if appends < 4:
                    with source.open("ab", buffering=0) as handle:
                        handle.write(content)
                    appends += 1

        started = time.monotonic()
        with mock.patch.object(
            profile_snapshot, "_write_descriptor", side_effect=write_then_grow
        ):
            with self.assertRaises(ProfileSnapshotError) as caught:
                prepare_profile_snapshots(
                    self.manifest(self.profile("rick")),
                    self.scratch,
                    allow_missing=False,
                )

        self.assertGreaterEqual(appends, 1)
        self.assertEqual(copied_bytes, len(content))
        self.assertLess(time.monotonic() - started, 1.0)
        self.assertEqual(caught.exception.category, "invalid_local_profile")
        self.assertEqual(list(self.scratch.iterdir()), [])

    def test_owned_file_premature_eof_is_rejected_directly(self) -> None:
        home = self.write_profile("rick", ["SOUL.md"])
        source = home / "SOUL.md"
        content = b"bounded-source" * 128
        source.write_bytes(content)
        source_status = source.stat()
        original_read = os.read
        source_reads = 0
        delivered = 0

        def read_then_end_early(descriptor: int, count: int) -> bytes:
            nonlocal delivered, source_reads
            status = os.fstat(descriptor)
            if (status.st_dev, status.st_ino) != (
                source_status.st_dev,
                source_status.st_ino,
            ):
                return original_read(descriptor, count)
            source_reads += 1
            if source_reads == 1:
                chunk = original_read(descriptor, min(count, len(content) // 2))
                delivered += len(chunk)
                return chunk
            return b""

        with mock.patch.object(
            profile_snapshot.os, "read", side_effect=read_then_end_early
        ):
            with self.assertRaises(ProfileSnapshotError) as caught:
                prepare_profile_snapshots(
                    self.manifest(self.profile("rick")),
                    self.scratch,
                    allow_missing=False,
                )

        self.assertEqual(source_reads, 2)
        self.assertEqual(delivered, len(content) // 2)
        self.assertEqual(caught.exception.category, "invalid_local_profile")
        self.assertEqual(list(self.scratch.iterdir()), [])

    def test_second_directory_dup_failure_closes_first_dup_and_cleans_snapshot(self) -> None:
        home = self.write_profile("rick", ["SOUL.md"])
        (home / "SOUL.md").write_text("safe\n", encoding="utf-8")
        original_dup = os.dup
        baseline_fds = len(os.listdir("/proc/self/fd"))
        dup_calls = 0
        first_duplicate: int | None = None
        observed_fds = baseline_fds
        first_duplicate_open = False

        def fail_second_dup(descriptor: int) -> int:
            nonlocal dup_calls, first_duplicate
            dup_calls += 1
            if dup_calls == 1:
                first_duplicate = original_dup(descriptor)
                return first_duplicate
            if dup_calls == 2:
                raise OSError(errno.EIO, "injected second dup failure")
            return original_dup(descriptor)

        try:
            with mock.patch.object(
                profile_snapshot.os, "dup", side_effect=fail_second_dup
            ):
                with self.assertRaises(ProfileSnapshotError) as caught:
                    prepare_profile_snapshots(
                        self.manifest(self.profile("rick")),
                        self.scratch,
                        allow_missing=False,
                    )
            observed_fds = len(os.listdir("/proc/self/fd"))
            assert first_duplicate is not None
            try:
                os.fstat(first_duplicate)
                first_duplicate_open = True
            except OSError as error:
                self.assertEqual(error.errno, errno.EBADF)
        finally:
            if first_duplicate_open and first_duplicate is not None:
                os.close(first_duplicate)

        self.assertEqual(dup_calls, 3)
        self.assertEqual(caught.exception.category, "invalid_local_profile")
        self.assertEqual(list(self.scratch.iterdir()), [])
        self.assertFalse(first_duplicate_open)
        self.assertEqual(observed_fds, baseline_fds)

    def test_output_directory_creation_failure_closes_open_source_child(self) -> None:
        cases = (
            ("declared", ["assets"], "assets", "assets"),
            ("recursive", ["assets"], "assets/nested", "assets/nested"),
            (
                "ancestor",
                ["assets/nested/SOUL.md"],
                "assets/nested/SOUL.md",
                "assets",
            ),
        )

        for index, (case, owned, source_item, failure_path) in enumerate(cases):
            with self.subTest(case=case):
                name = f"fdcreate{index}"
                home = self.write_profile(name, owned)
                source_path = home / source_item
                if source_path.suffix:
                    source_path.parent.mkdir(parents=True)
                    source_path.write_text("safe\n", encoding="utf-8")
                else:
                    source_path.mkdir(parents=True)
                    (source_path / "safe.txt").write_text(
                        "safe\n", encoding="utf-8"
                    )
                scratch = self.root / f"fd-create-scratch-{index}"
                scratch.mkdir(mode=0o700)
                original_open_source = profile_snapshot._open_source_directory
                original_create = profile_snapshot._create_output_directory
                baseline_fds = len(os.listdir("/proc/self/fd"))
                opened_child: int | None = None
                create_failures = 0
                source_was_open = False

                def track_source_child(parent_fd: int, child_name: str):
                    nonlocal opened_child
                    result = original_open_source(parent_fd, child_name)
                    relative_name = failure_path.rsplit("/", 1)[-1]
                    if child_name == relative_name:
                        opened_child = result[0]
                    return result

                def fail_output_create(
                    parent_fd: int,
                    child_name: str,
                    relative: object,
                    expected_directories: object,
                ) -> int:
                    nonlocal create_failures, source_was_open
                    if relative.as_posix() == failure_path:
                        create_failures += 1
                        if opened_child is not None:
                            os.fstat(opened_child)
                            source_was_open = True
                        raise OSError(
                            errno.EIO, "injected output directory failure"
                        )
                    return original_create(
                        parent_fd,
                        child_name,
                        relative,
                        expected_directories,
                    )

                with mock.patch.object(
                    profile_snapshot,
                    "_open_source_directory",
                    side_effect=track_source_child,
                ), mock.patch.object(
                    profile_snapshot,
                    "_create_output_directory",
                    side_effect=fail_output_create,
                ):
                    with self.assertRaises(ProfileSnapshotError) as caught:
                        prepare_profile_snapshots(
                            self.manifest(self.profile(name)),
                            scratch,
                            allow_missing=False,
                        )

                observed_fds = len(os.listdir("/proc/self/fd"))
                child_still_open = False
                assert opened_child is not None
                try:
                    os.fstat(opened_child)
                    child_still_open = True
                except OSError as error:
                    self.assertEqual(error.errno, errno.EBADF)
                finally:
                    if child_still_open:
                        os.close(opened_child)

                self.assertEqual(create_failures, 1)
                self.assertTrue(source_was_open)
                self.assertEqual(
                    caught.exception.category, "invalid_local_profile"
                )
                self.assertEqual(list(scratch.iterdir()), [])
                self.assertFalse(child_still_open)
                self.assertEqual(observed_fds, baseline_fds)

    def test_retained_fd_budget_rejects_before_emfile_and_cleans_all_profiles(self) -> None:
        first = self.write_profile("alpha", ["SOUL.md"])
        (first / "SOUL.md").write_text("first\n", encoding="utf-8")
        second = self.write_profile("beta", ["assets"])
        assets = second / "assets"
        assets.mkdir()
        for index in range(128):
            (assets / f"item-{index:03}.txt").write_text(
                f"item {index}\n", encoding="utf-8"
            )

        original_limits = resource.getrlimit(resource.RLIMIT_NOFILE)
        original_open = os.open
        baseline_open = len(os.listdir("/proc/self/fd"))
        effective_limit = baseline_open + 80
        emfile_attempted = False

        def guarded_open(
            path: str | bytes | os.PathLike[str],
            flags: int,
            mode: int = 0o777,
            *,
            dir_fd: int | None = None,
        ) -> int:
            nonlocal emfile_attempted
            if len(os.listdir("/proc/self/fd")) >= effective_limit:
                emfile_attempted = True
                raise OSError(errno.EMFILE, "mock descriptor limit")
            return original_open(path, flags, mode, dir_fd=dir_fd)

        hard_limit = max(effective_limit, original_limits[1])
        with mock.patch.object(
            resource,
            "getrlimit",
            return_value=(effective_limit, hard_limit),
        ) as getrlimit, mock.patch.object(
            profile_snapshot.os, "open", side_effect=guarded_open
        ), mock.patch.object(
            profile_snapshot, "_prepare_one", wraps=profile_snapshot._prepare_one
        ) as prepare_one:
            with self.assertRaises(ProfileSnapshotError) as caught:
                prepare_profile_snapshots(
                    self.manifest(self.profile("alpha"), self.profile("beta")),
                    self.scratch,
                    allow_missing=False,
                )

        getrlimit.assert_called_once_with(resource.RLIMIT_NOFILE)
        self.assertEqual(prepare_one.call_count, 2)
        self.assertFalse(emfile_attempted)
        self.assertEqual(caught.exception.category, "resource_limit")
        self.assertEqual(list(self.scratch.iterdir()), [])
        self.assertEqual(len(os.listdir("/proc/self/fd")), baseline_open)
        self.assertEqual(
            resource.getrlimit(resource.RLIMIT_NOFILE), original_limits
        )

    def test_accepts_an_owned_file_larger_than_sixteen_mebibytes(self) -> None:
        home = self.write_profile("rick", ["archive.bin"])
        large = home / "archive.bin"
        with large.open("wb") as handle:
            handle.seek(16 * 1024 * 1024)
            handle.write(b"\0")
        scratch = self.root / "large-file"
        scratch.mkdir(mode=0o700)

        snapshot = prepare_profile_snapshots(self.manifest(self.profile("rick")), scratch, allow_missing=False).snapshots[0]

        self.assertEqual(snapshot.entries[0].size, 16 * 1024 * 1024 + 1)
        self.assertEqual((snapshot.root / "archive.bin").stat().st_size, 16 * 1024 * 1024 + 1)

    def test_rejects_links_special_files_hardlinks_and_unreadable_files(self) -> None:
        home = self.write_profile("rick", ["assets"])
        (home / "assets").mkdir()
        (home / "assets" / "link").symlink_to("elsewhere")
        with self.assertRaises(ProfileSnapshotError):
            prepare_profile_snapshots(self.manifest(self.profile("rick")), self.scratch, allow_missing=False)

        for kind in ("fifo", "socket", "hardlink", "unreadable"):
            with self.subTest(kind=kind):
                for child in (home / "assets").iterdir():
                    child.unlink()
                path = home / "assets" / kind
                if kind == "fifo":
                    os.mkfifo(path)
                elif kind == "socket":
                    server = socket.socket(socket.AF_UNIX)
                    self.addCleanup(server.close)
                    server.bind(str(path))
                else:
                    path.write_text("safe\n", encoding="utf-8")
                    if kind == "hardlink":
                        os.link(path, home / "extra-link")
                    else:
                        path.chmod(0)
                with self.assertRaises(ProfileSnapshotError):
                    prepare_profile_snapshots(self.manifest(self.profile("rick")), self.scratch, allow_missing=False)
                if kind == "unreadable":
                    path.chmod(0o600)
                if kind == "hardlink":
                    (home / "extra-link").unlink()

    def test_rejects_a_manifest_fifo_without_waiting_for_a_writer(self) -> None:
        home = self.write_profile("rick", ["SOUL.md"])
        (home / "SOUL.md").write_text("safe\n", encoding="utf-8")
        (home / "distribution.yaml").unlink()
        os.mkfifo(home / "distribution.yaml")
        timed_out = False

        def stop_blocking(_signum: int, _frame: object) -> None:
            nonlocal timed_out
            timed_out = True
            raise TimeoutError("manifest FIFO open blocked")

        previous = signal.signal(signal.SIGALRM, stop_blocking)
        started = time.monotonic()
        signal.setitimer(signal.ITIMER_REAL, 0.5)
        try:
            with self.assertRaises(ProfileSnapshotError) as caught:
                prepare_profile_snapshots(
                    self.manifest(self.profile("rick")), self.scratch, allow_missing=False
                )
        finally:
            signal.setitimer(signal.ITIMER_REAL, 0)
            signal.signal(signal.SIGALRM, previous)

        self.assertFalse(timed_out, "opening a manifest FIFO blocked")
        self.assertLess(time.monotonic() - started, 0.5)
        self.assertEqual(caught.exception.category, "invalid_local_profile")

    def test_snapshot_is_deterministic_and_contains_only_owned_projection(self) -> None:
        rick = self.write_profile("rick", ["assets", "SOUL.md"])
        (rick / "SOUL.md").write_text("Rick\n", encoding="utf-8")
        (rick / "assets").mkdir()
        (rick / "assets" / "avatar.png").write_bytes(b"rick-avatar")
        (rick / "unowned.txt").write_text("not mirrored\n", encoding="utf-8")
        hoffman = self.write_profile("hoffman", ["portfolio.pdf"])
        (hoffman / "portfolio.pdf").write_bytes(b"hoffman-portfolio")
        risa = self.write_profile("risarisa", ["SOUL.md"])
        (risa / "SOUL.md").write_text("RisaRisa\n", encoding="utf-8")

        prepared = prepare_profile_snapshots(
            self.manifest(self.profile("rick"), self.profile("hoffman"), self.profile("risarisa")), self.scratch, allow_missing=False
        )
        snapshots = {snapshot.declaration.name: snapshot for snapshot in prepared.snapshots}
        self.assertEqual([entry.path.as_posix() for entry in snapshots["rick"].entries], ["SOUL.md", "assets/avatar.png"])
        self.assertEqual([entry.path.as_posix() for entry in snapshots["hoffman"].entries], ["portfolio.pdf"])
        self.assertNotIn("assets", [entry.path.parts[0] for entry in snapshots["risarisa"].entries])
        self.assertEqual(sorted(path.relative_to(snapshots["rick"].root).as_posix() for path in snapshots["rick"].root.rglob("*") if path.is_file()), [".gitignore", "SOUL.md", "assets/avatar.png", "distribution.yaml"])
        again_root = self.root / "again"
        again_root.mkdir(mode=0o700)
        again = prepare_profile_snapshots(self.manifest(self.profile("rick")), again_root, allow_missing=False)
        self.assertEqual(snapshots["rick"].digest, again.snapshots[0].digest)

    def test_missing_profiles_are_reported_only_when_allowed(self) -> None:
        profile = self.profile("rick")
        self.assertEqual(prepare_profile_snapshots(self.manifest(profile), self.scratch, allow_missing=True).missing, (profile,))
        with self.assertRaises(ProfileSnapshotError):
            prepare_profile_snapshots(self.manifest(profile), self.scratch, allow_missing=False)

    def test_revalidation_rejects_every_late_local_profile_drift(self) -> None:
        def reset_profile() -> None:
            shutil.rmtree(self.data_root / "profiles", ignore_errors=True)
            for child in self.scratch.iterdir():
                shutil.rmtree(child)

        def prepare_existing(owned: list[str]) -> tuple[BootstrapManifest, object, Path]:
            home = self.write_profile("rick", owned)
            for item in owned:
                path = home / item
                if item == "assets":
                    path.mkdir()
                    (path / "fixture.txt").write_bytes(b"safe\n")
                else:
                    path.write_bytes(b"safe\n")
            configured = self.manifest(self.profile("rick"))
            baseline = prepare_profile_snapshots(
                configured, self.scratch, allow_missing=True
            )
            return configured, baseline, home

        cases = (
            "canonical-manifest-edit",
            "same-size-content-edit",
            "owned-file-mode-change",
            "owned-file-addition",
            "owned-file-deletion",
            "owned-file-rename",
            "owned-directory-replacement",
            "previously-missing-target-creation",
            "previously-existing-target-deletion",
        )
        for case in cases:
            with self.subTest(case=case):
                reset_profile()
                owned = ["assets"] if case in {
                    "owned-file-addition",
                    "owned-directory-replacement",
                } else ["SOUL.md"]
                if case == "previously-missing-target-creation":
                    configured = self.manifest(self.profile("rick"))
                    baseline = prepare_profile_snapshots(
                        configured, self.scratch, allow_missing=True
                    )
                    home = self.write_profile("rick", owned)
                    (home / "SOUL.md").write_bytes(b"late\n")
                else:
                    configured, baseline, home = prepare_existing(owned)
                    if case == "canonical-manifest-edit":
                        manifest_path = home / "distribution.yaml"
                        payload = yaml.safe_load(
                            manifest_path.read_text(encoding="utf-8")
                        )
                        payload["version"] = "0.2.0"
                        manifest_path.write_text(
                            yaml.safe_dump(payload, sort_keys=False),
                            encoding="utf-8",
                        )
                    elif case == "same-size-content-edit":
                        path = home / "SOUL.md"
                        before = path.stat()
                        path.write_bytes(b"late\n")
                        os.utime(
                            path,
                            ns=(before.st_atime_ns, before.st_mtime_ns),
                        )
                    elif case == "owned-file-mode-change":
                        (home / "SOUL.md").chmod(0o755)
                    elif case == "owned-file-addition":
                        (home / "assets" / "late.txt").write_bytes(b"late\n")
                    elif case == "owned-file-deletion":
                        (home / "SOUL.md").unlink()
                    elif case == "owned-file-rename":
                        (home / "SOUL.md").rename(home / "MIND.md")
                    elif case == "owned-directory-replacement":
                        shutil.rmtree(home / "assets")
                        (home / "assets").mkdir()
                        (home / "assets" / "replacement.txt").write_bytes(
                            b"late\n"
                        )
                    elif case == "previously-existing-target-deletion":
                        shutil.rmtree(home)

                with self.assertRaises(ProfileSnapshotError) as caught:
                    profile_snapshot.revalidate_profile_snapshots(
                        configured,
                        baseline,
                        self.scratch,
                    )

                self.assertEqual(caught.exception.profile, "rick")
                self.assertEqual(
                    caught.exception.category,
                    "local_profile_changed",
                )

    def test_unchanged_revalidation_passes_and_removes_comparison_scratch(
        self,
    ) -> None:
        configured = self.manifest(self.profile("rick"))
        self.write_profile("rick", ["SOUL.md"])
        (self.profile("rick").target / "SOUL.md").write_bytes(b"safe\n")
        baseline = prepare_profile_snapshots(
            configured,
            self.scratch,
            allow_missing=True,
        )
        before = tuple(self.scratch.iterdir())

        profile_snapshot.revalidate_profile_snapshots(
            configured,
            baseline,
            self.scratch,
        )

        self.assertEqual(tuple(self.scratch.iterdir()), before)

    def test_revalidation_cleanup_failure_overrides_an_unchanged_result(
        self,
    ) -> None:
        home = self.write_profile("rick", ["SOUL.md"])
        (home / "SOUL.md").write_bytes(b"safe\n")
        configured = self.manifest(self.profile("rick"))
        baseline = prepare_profile_snapshots(
            configured,
            self.scratch,
            allow_missing=True,
        )
        comparison = self.root / "comparison-cleanup-failure"
        comparison.mkdir(mode=0o700)
        resource = mock.Mock(path=comparison)
        resource.cleanup.return_value = False

        with (
            mock.patch.object(
                profile_snapshot,
                "create_private_directory",
                return_value=resource,
            ),
            self.assertRaises(ProfileSnapshotError) as caught,
        ):
            profile_snapshot.revalidate_profile_snapshots(
                configured,
                baseline,
                self.scratch,
            )

        self.assertEqual(caught.exception.profile, "rick")
        self.assertEqual(caught.exception.category, "cleanup_failed")

    def test_revalidation_cleanup_failure_overrides_detected_drift(
        self,
    ) -> None:
        home = self.write_profile("rick", ["SOUL.md"])
        (home / "SOUL.md").write_bytes(b"safe\n")
        configured = self.manifest(self.profile("rick"))
        baseline = prepare_profile_snapshots(
            configured,
            self.scratch,
            allow_missing=True,
        )
        (home / "SOUL.md").write_bytes(b"late\n")
        comparison = self.root / "drift-cleanup-failure"
        comparison.mkdir(mode=0o700)
        resource = mock.Mock(path=comparison)
        resource.cleanup.return_value = False

        with (
            mock.patch.object(
                profile_snapshot,
                "create_private_directory",
                return_value=resource,
            ),
            self.assertRaises(ProfileSnapshotError) as caught,
        ):
            profile_snapshot.revalidate_profile_snapshots(
                configured,
                baseline,
                self.scratch,
            )

        self.assertEqual(caught.exception.profile, "rick")
        self.assertEqual(caught.exception.category, "cleanup_failed")

    def test_revalidation_reports_the_first_manifest_order_mismatch(
        self,
    ) -> None:
        rick = self.write_profile("rick", ["SOUL.md"])
        hoffman = self.write_profile("hoffman", ["SOUL.md"])
        for home in (rick, hoffman):
            (home / "SOUL.md").write_bytes(b"safe\n")
        configured = self.manifest(
            self.profile("rick"),
            self.profile("hoffman"),
        )
        baseline = prepare_profile_snapshots(
            configured,
            self.scratch,
            allow_missing=True,
        )
        (rick / "SOUL.md").write_bytes(b"rick\n")
        (hoffman / "SOUL.md").write_bytes(b"hoff\n")

        with self.assertRaises(ProfileSnapshotError) as caught:
            profile_snapshot.revalidate_profile_snapshots(
                configured,
                baseline,
                self.scratch,
            )

        self.assertEqual(caught.exception.profile, "rick")
        self.assertEqual(
            caught.exception.category,
            "local_profile_changed",
        )

    def test_all_missing_profiles_still_recheck_scratch_at_the_end(self) -> None:
        profiles = (self.profile("rick"), self.profile("hoffman"))
        original_exists = profile_snapshot._path_exists
        probes = 0
        changed = False

        def probe_then_chmod(path: Path) -> bool:
            nonlocal probes, changed
            exists = original_exists(path)
            probes += 1
            if probes == len(profiles):
                self.scratch.chmod(0o755)
                changed = True
            return exists

        try:
            with mock.patch.object(
                profile_snapshot, "_path_exists", side_effect=probe_then_chmod
            ):
                with self.assertRaises(ProfileSnapshotError) as caught:
                    prepare_profile_snapshots(
                        self.manifest(*profiles), self.scratch, allow_missing=True
                    )
        finally:
            self.scratch.chmod(0o700)

        self.assertTrue(changed)
        self.assertEqual(probes, 2)
        self.assertEqual(caught.exception.profile, "hoffman")
        self.assertEqual(caught.exception.category, "invalid_local_profile")
        self.assertEqual(list(self.scratch.iterdir()), [])

    def test_rejects_group_or_world_accessible_scratch(self) -> None:
        home = self.write_profile("rick", ["SOUL.md"])
        (home / "SOUL.md").write_text("safe\n", encoding="utf-8")
        self.scratch.chmod(0o750)
        with self.assertRaises(ValueError):
            prepare_profile_snapshots(self.manifest(self.profile("rick")), self.scratch, allow_missing=False)

    def test_rejects_scratch_permissions_changed_after_snapshot_verification(self) -> None:
        home = self.write_profile("rick", ["SOUL.md"])
        (home / "SOUL.md").write_text("safe\n", encoding="utf-8")
        original_verify = profile_snapshot._verify_prepared_snapshot
        verify_calls = 0
        changed = False

        def verify_then_chmod(*args: object, **kwargs: object) -> None:
            nonlocal verify_calls, changed
            original_verify(*args, **kwargs)
            verify_calls += 1
            if verify_calls == 2:
                self.scratch.chmod(0o755)
                changed = True

        try:
            with mock.patch.object(
                profile_snapshot, "_verify_prepared_snapshot", side_effect=verify_then_chmod
            ):
                with self.assertRaises(ProfileSnapshotError) as caught:
                    prepare_profile_snapshots(
                        self.manifest(self.profile("rick")), self.scratch, allow_missing=False
                    )
        finally:
            self.scratch.chmod(0o700)

        self.assertTrue(changed)
        self.assertEqual(verify_calls, 2)
        self.assertEqual(caught.exception.category, "invalid_local_profile")
        self.assertFalse((self.scratch / "rick").exists())

    def test_target_probe_error_is_redacted_and_cleans_earlier_snapshots(self) -> None:
        rick = self.write_profile("rick", ["SOUL.md"])
        (rick / "SOUL.md").write_text("safe\n", encoding="utf-8")
        hoffman = self.write_profile("hoffman", ["portfolio.pdf"])
        (hoffman / "portfolio.pdf").write_bytes(b"portfolio")
        original_exists = profile_snapshot._path_exists
        probe_failed = False

        def fail_second_probe(path: Path) -> bool:
            nonlocal probe_failed
            if path == hoffman:
                probe_failed = True
                raise PermissionError("private probe detail")
            return original_exists(path)

        with mock.patch.object(profile_snapshot, "_path_exists", side_effect=fail_second_probe):
            with self.assertRaises(ProfileSnapshotError) as caught:
                prepare_profile_snapshots(
                    self.manifest(self.profile("rick"), self.profile("hoffman")),
                    self.scratch,
                    allow_missing=False,
                )

        self.assertTrue(probe_failed)
        self.assertEqual(caught.exception.profile, "hoffman")
        self.assertEqual(caught.exception.category, "invalid_local_profile")
        self.assertEqual(str(caught.exception), "profile snapshot rejected (invalid_local_profile)")
        self.assertFalse((self.scratch / "rick").exists())

    def test_scratch_rename_and_symlink_swap_cannot_redirect_snapshot_writes(self) -> None:
        home = self.write_profile("rick", ["SOUL.md"])
        (home / "SOUL.md").write_text("safe\n", encoding="utf-8")
        scratch = self.root / "swap-scratch"
        scratch.mkdir(mode=0o700)
        moved = self.root / "moved-scratch"
        outside = self.root / "outside"
        outside.mkdir()
        original_fchmod = os.fchmod
        swapped = False

        def fchmod_then_swap(descriptor: int, mode: int) -> None:
            nonlocal swapped
            original_fchmod(descriptor, mode)
            if not swapped:
                swapped = True
                scratch.rename(moved)
                scratch.symlink_to(outside, target_is_directory=True)

        with mock.patch("hermes_bootstrap.profile_snapshot.os.fchmod", side_effect=fchmod_then_swap):
            with self.assertRaises(ProfileSnapshotError) as caught:
                prepare_profile_snapshots(self.manifest(self.profile("rick")), scratch, allow_missing=False)
        self.assertEqual(caught.exception.category, "invalid_local_profile")
        self.assertFalse((outside / "rick" / "SOUL.md").exists())
        self.assertFalse((moved / "rick").exists())

    def test_rejects_profile_names_that_cannot_be_safe_scratch_components(self) -> None:
        for index, name in enumerate(("../outside", "rick/morty", r"rick\morty", ".", "..", "Rick", "rick_", "rick.", "rick ")):
            with self.subTest(name=name):
                target = self.data_root / "profiles" / name
                target.mkdir(parents=True, exist_ok=True)
                (target / "distribution.yaml").write_text(
                    yaml.safe_dump(
                        {"name": name, "version": "0.1.0", "hermes_requires": ">=0.18.2", "distribution_owned": ["SOUL.md"]},
                        sort_keys=False,
                    ),
                    encoding="utf-8",
                )
                (target / "SOUL.md").write_text("safe\n", encoding="utf-8")
                declaration = DistributionSource(name, "https://github.com/rurusasu/hermes-profile-rick.git", "main", target, "distribution.yaml")
                scratch = self.root / f"unsafe-name-{index}"
                scratch.mkdir(mode=0o700)
                with self.assertRaises(ProfileSnapshotError):
                    prepare_profile_snapshots(self.manifest(declaration), scratch, allow_missing=False)
                self.assertFalse((self.root / "outside").exists())
                self.assertEqual(list(scratch.iterdir()), [])

    def test_rejects_an_external_target_and_preserves_executable_git_mode(self) -> None:
        home = self.write_profile("rick", ["tools/sync"])
        executable = home / "tools" / "sync"
        executable.parent.mkdir()
        executable.write_text("#!/bin/sh\n", encoding="utf-8")
        executable.chmod(0o755)
        snapshot = prepare_profile_snapshots(self.manifest(self.profile("rick")), self.scratch, allow_missing=False).snapshots[0]
        self.assertEqual(snapshot.entries[0].mode, 0o755)
        self.assertEqual(stat.S_IMODE((snapshot.root / "tools" / "sync").stat().st_mode), 0o755)

        external = DistributionSource("rick", "https://github.com/rurusasu/hermes-profile-rick.git", "main", self.root / "outside", "distribution.yaml")
        external_scratch = self.root / "external"
        external_scratch.mkdir(mode=0o700)
        with self.assertRaises(ProfileSnapshotError):
            prepare_profile_snapshots(self.manifest(external), external_scratch, allow_missing=False)

    def test_case_collision_and_real_file_replacement_are_rejected_and_cleaned_up(self) -> None:
        home = self.write_profile("rick", ["assets"])
        (home / "assets").mkdir()
        (home / "assets" / "Avatar.png").write_bytes(b"one")
        (home / "assets" / "avatar.png").write_bytes(b"two")
        with self.assertRaises(ProfileSnapshotError):
            prepare_profile_snapshots(self.manifest(self.profile("rick")), self.scratch, allow_missing=False)
        self.assertFalse((self.scratch / "rick").exists())

        (home / "assets" / "avatar.png").unlink()
        replacement = self.root / "replacement.txt"
        replacement.write_text("replacement\n", encoding="utf-8")
        original_write = profile_snapshot._write_descriptor
        replaced = False

        def write_then_replace(descriptor: int, content: bytes) -> None:
            nonlocal replaced
            original_write(descriptor, content)
            if content == b"one" and not replaced:
                os.replace(replacement, home / "assets" / "Avatar.png")
                replaced = True

        with mock.patch("hermes_bootstrap.profile_snapshot._write_descriptor", side_effect=write_then_replace):
            with self.assertRaises(ProfileSnapshotError) as caught:
                prepare_profile_snapshots(self.manifest(self.profile("rick")), self.scratch, allow_missing=False)
        self.assertTrue(replaced)
        self.assertEqual(caught.exception.category, "invalid_local_profile")
        self.assertFalse((self.scratch / "rick").exists())

    def test_rejects_case_colliding_ancestors_and_control_name_variants(self) -> None:
        home = self.write_profile("rick", ["Assets/a.txt", "assets/b.txt"])
        (home / "Assets").mkdir()
        (home / "Assets" / "a.txt").write_text("one\n", encoding="utf-8")
        (home / "assets").mkdir()
        (home / "assets" / "b.txt").write_text("two\n", encoding="utf-8")
        with self.assertRaises(ProfileSnapshotError) as caught:
            prepare_profile_snapshots(self.manifest(self.profile("rick")), self.scratch, allow_missing=False)
        self.assertEqual(caught.exception.category, "invalid_local_profile")
        self.assertFalse((self.scratch / "rick").exists())

        for index, control in enumerate(("Distribution.yaml", ".GitIgnore")):
            with self.subTest(control=control):
                name = f"control{index}"
                profile_home = self.write_profile(name, [control])
                (profile_home / control).write_text("not a control file\n", encoding="utf-8")
                scratch = self.root / f"control-scratch-{index}"
                scratch.mkdir(mode=0o700)
                with self.assertRaises(ProfileSnapshotError) as control_error:
                    prepare_profile_snapshots(self.manifest(self.profile(name)), scratch, allow_missing=False)
                self.assertEqual(control_error.exception.category, "invalid_local_profile")
                self.assertEqual(list(scratch.iterdir()), [])

    def test_rejects_git_metadata_names_at_any_depth(self) -> None:
        for index, control in enumerate((".git", ".gitignore", ".gitattributes", ".gitmodules")):
            with self.subTest(control=control):
                name = f"nested{index}"
                home = self.write_profile(name, ["assets"])
                nested = home / "assets" / "nested"
                nested.mkdir(parents=True)
                candidate = nested / control
                if control == ".git":
                    candidate.mkdir()
                    (candidate / "config").write_text("[core]\n", encoding="utf-8")
                else:
                    candidate.write_text("unsafe\n", encoding="utf-8")
                scratch = self.root / f"nested-control-{index}"
                scratch.mkdir(mode=0o700)
                with self.assertRaises(ProfileSnapshotError) as caught:
                    prepare_profile_snapshots(self.manifest(self.profile(name)), scratch, allow_missing=False)
                self.assertEqual(caught.exception.category, "invalid_local_profile")
                self.assertEqual(list(scratch.iterdir()), [])

    def test_rejects_a_hardlink_created_while_streaming(self) -> None:
        home = self.write_profile("rick", ["SOUL.md"])
        content = b"link-during-copy\n"
        source = home / "SOUL.md"
        source.write_bytes(content)
        external_link = self.root / "late-hardlink"
        original_write = profile_snapshot._write_descriptor
        linked = False

        def write_then_link(descriptor: int, chunk: bytes) -> None:
            nonlocal linked
            original_write(descriptor, chunk)
            if chunk == content and not linked:
                os.link(source, external_link)
                linked = True

        with mock.patch("hermes_bootstrap.profile_snapshot._write_descriptor", side_effect=write_then_link):
            with self.assertRaises(ProfileSnapshotError) as caught:
                prepare_profile_snapshots(self.manifest(self.profile("rick")), self.scratch, allow_missing=False)
        self.assertTrue(linked)
        self.assertEqual(caught.exception.category, "invalid_local_profile")
        self.assertFalse((self.scratch / "rick").exists())

    def test_final_attestation_rejects_a_snapshot_output_hardlink_without_damaging_it(self) -> None:
        home = self.write_profile("rick", ["SOUL.md"])
        content = b"snapshot-output-hardlink\n"
        (home / "SOUL.md").write_bytes(content)
        external_link = self.root / "snapshot-output-hardlink"
        original_attest = profile_snapshot._final_attest_prepared_snapshot
        linked = False

        def link_then_attest(*args: object, **kwargs: object) -> None:
            nonlocal linked
            if not linked:
                os.link(self.scratch / "rick" / "SOUL.md", external_link)
                linked = True
            original_attest(*args, **kwargs)

        with mock.patch.object(
            profile_snapshot,
            "_final_attest_prepared_snapshot",
            side_effect=link_then_attest,
        ) as attest:
            with self.assertRaises(ProfileSnapshotError) as caught:
                prepare_profile_snapshots(
                    self.manifest(self.profile("rick")),
                    self.scratch,
                    allow_missing=False,
                )

        self.assertTrue(linked)
        attest.assert_called_once()
        self.assertEqual(caught.exception.category, "invalid_local_profile")
        self.assertEqual(external_link.read_bytes(), content)
        self.assertEqual(external_link.stat().st_nlink, 1)
        self.assertEqual(list(self.scratch.iterdir()), [])

    def test_rejects_same_uid_destination_replacement_before_return(self) -> None:
        home = self.write_profile("rick", ["SOUL.md"])
        content = b"canonical-snapshot-content\n"
        (home / "SOUL.md").write_bytes(content)
        replacement = self.root / "destination-replacement"
        marker = b"altered-after-copy\n"
        replacement.write_bytes(marker)
        replacement_inode = replacement.stat().st_ino
        original_write = profile_snapshot._write_descriptor
        replaced = False

        def write_then_replace(descriptor: int, chunk: bytes) -> None:
            nonlocal replaced
            original_write(descriptor, chunk)
            if chunk == content and not replaced:
                os.replace(replacement, self.scratch / "rick" / "SOUL.md")
                replaced = True

        with mock.patch("hermes_bootstrap.profile_snapshot._write_descriptor", side_effect=write_then_replace):
            with self.assertRaises(ProfileSnapshotError) as caught:
                prepare_profile_snapshots(self.manifest(self.profile("rick")), self.scratch, allow_missing=False)
        self.assertTrue(replaced)
        self.assertEqual(caught.exception.category, "cleanup_failed")
        retained = self.scratch / "rick" / "SOUL.md"
        self.assertEqual(retained.stat().st_ino, replacement_inode)
        self.assertEqual(retained.read_bytes(), marker)

    def test_failure_cleanup_retains_the_unlinked_registered_output_inode(self) -> None:
        home = self.write_profile("rick", ["SOUL.md"])
        source_content = b"registered-output\n"
        (home / "SOUL.md").write_bytes(source_content)
        marker = b"replacement-must-survive\n"
        original_verify = profile_snapshot._verify_destination_descriptor
        original_remove = profile_snapshot._remove_snapshot
        old_identity: tuple[int, int] | None = None
        replacement_identity: tuple[int, int] | None = None
        retained_descriptor: int | None = None
        retained_identity: tuple[int, int] | None = None
        retained_nlink: int | None = None
        replacements = 0

        def replace_then_verify(
            parent_fd: int,
            name: str,
            descriptor: int,
            mode: int,
            size: int,
        ) -> os.stat_result:
            nonlocal old_identity, replacement_identity, replacements
            if name == "SOUL.md":
                self.assertEqual(replacements, 0)
                status = os.fstat(descriptor)
                old_identity = (status.st_dev, status.st_ino)
                os.unlink(name, dir_fd=parent_fd)
                replacement_fd = os.open(
                    name,
                    os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC,
                    mode,
                    dir_fd=parent_fd,
                )
                try:
                    os.write(replacement_fd, marker)
                    os.fchmod(replacement_fd, mode)
                finally:
                    os.close(replacement_fd)
                replacement = os.stat(
                    name, dir_fd=parent_fd, follow_symlinks=False
                )
                replacement_identity = (replacement.st_dev, replacement.st_ino)
                self.assertNotEqual(replacement_identity, old_identity)
                replacements += 1
            return original_verify(parent_fd, name, descriptor, mode, size)

        def inspect_then_remove(
            scratch_fd: int,
            output_fd: int | None,
            expected_identity: tuple[int, int],
            files: tuple[object, ...],
            directories: tuple[object, ...],
        ) -> None:
            nonlocal retained_descriptor, retained_identity, retained_nlink
            expected = next(
                item for item in files if item.path.as_posix() == "SOUL.md"
            )
            retained_descriptor = getattr(expected, "descriptor", None)
            if retained_descriptor is not None:
                retained = os.fstat(retained_descriptor)
                retained_identity = (retained.st_dev, retained.st_ino)
                retained_nlink = retained.st_nlink
            original_remove(
                scratch_fd,
                output_fd,
                expected_identity,
                files,
                directories,
            )

        with mock.patch.object(
            profile_snapshot,
            "_verify_destination_descriptor",
            side_effect=replace_then_verify,
        ), mock.patch.object(
            profile_snapshot, "_remove_snapshot", side_effect=inspect_then_remove
        ):
            with self.assertRaises(ProfileSnapshotError) as caught:
                prepare_profile_snapshots(
                    self.manifest(self.profile("rick")),
                    self.scratch,
                    allow_missing=False,
                )

        self.assertEqual(replacements, 1)
        self.assertIsNotNone(retained_descriptor)
        self.assertEqual(retained_identity, old_identity)
        self.assertEqual(retained_nlink, 0)
        self.assertEqual(caught.exception.category, "cleanup_failed")
        replacement = self.scratch / "rick" / "SOUL.md"
        self.assertEqual(
            (replacement.stat().st_dev, replacement.stat().st_ino),
            replacement_identity,
        )
        self.assertEqual(replacement.read_bytes(), marker)
        assert retained_descriptor is not None
        with self.assertRaises(OSError):
            os.fstat(retained_descriptor)

    def test_success_closes_all_retained_file_descriptors_after_attestation(self) -> None:
        home = self.write_profile("rick", ["SOUL.md"])
        (home / "SOUL.md").write_text("safe\n", encoding="utf-8")
        original_attest = profile_snapshot._final_attest_prepared_snapshot
        retained_descriptors: set[int] = set()

        def inspect_then_attest(
            scratch_root: Path,
            scratch_fd: int,
            prepared: object,
        ) -> None:
            for expected in prepared.files:
                os.fstat(expected.descriptor)
                retained_descriptors.add(expected.descriptor)
            original_attest(scratch_root, scratch_fd, prepared)

        with mock.patch.object(
            profile_snapshot,
            "_final_attest_prepared_snapshot",
            side_effect=inspect_then_attest,
        ) as attest:
            snapshot = prepare_profile_snapshots(
                self.manifest(self.profile("rick")),
                self.scratch,
                allow_missing=False,
            ).snapshots[0]

        attest.assert_called_once()
        self.assertEqual(len(retained_descriptors), 3)
        self.assertEqual((snapshot.root / "SOUL.md").read_text(), "safe\n")
        for descriptor in retained_descriptors:
            with self.assertRaises(OSError) as caught:
                os.fstat(descriptor)
            self.assertEqual(caught.exception.errno, errno.EBADF)

    def test_final_recursive_attestation_rejects_late_inventory_mutations(self) -> None:
        for index, mutation in enumerate(("insert", "delete", "replace")):
            with self.subTest(mutation=mutation):
                name = f"late{index}"
                home = self.write_profile(name, ["SOUL.md"])
                (home / "SOUL.md").write_text("safe\n", encoding="utf-8")
                scratch = self.root / f"late-attestation-{index}"
                scratch.mkdir(mode=0o700)
                replacement = self.root / f"late-replacement-{index}"
                replacement.write_bytes(b"evil\n")
                replacement_inode = replacement.stat().st_ino
                original_verify_file = profile_snapshot._verify_expected_file
                file_checks = 0
                mutated = False

                def verify_file_then_mutate(*args: object, **kwargs: object) -> None:
                    nonlocal file_checks, mutated
                    original_verify_file(*args, **kwargs)
                    file_checks += 1
                    if file_checks != 9:
                        return
                    snapshot_root = scratch / name
                    if mutation == "insert":
                        (snapshot_root / "late-unowned.txt").write_text(
                            "late\n", encoding="utf-8"
                        )
                    elif mutation == "delete":
                        (snapshot_root / "SOUL.md").unlink()
                    else:
                        os.replace(replacement, snapshot_root / "SOUL.md")
                    mutated = True

                with mock.patch.object(
                    profile_snapshot, "_verify_expected_file", side_effect=verify_file_then_mutate
                ):
                    with self.assertRaises(ProfileSnapshotError) as caught:
                        prepare_profile_snapshots(
                            self.manifest(self.profile(name)), scratch, allow_missing=False
                        )

                self.assertTrue(mutated)
                self.assertGreaterEqual(file_checks, 9)
                expected_category = (
                    "invalid_local_profile" if mutation == "insert" else "cleanup_failed"
                )
                self.assertEqual(caught.exception.category, expected_category)
                if mutation == "replace":
                    retained = scratch / name / "SOUL.md"
                    self.assertEqual(retained.stat().st_ino, replacement_inode)
                    self.assertEqual(retained.read_bytes(), b"evil\n")
                else:
                    self.assertEqual(list(scratch.iterdir()), [])

    def test_final_attestation_regular_to_fifo_swap_does_not_block(self) -> None:
        home = self.write_profile("rick", ["SOUL.md"])
        (home / "SOUL.md").write_text("safe\n", encoding="utf-8")
        original_verify_file = profile_snapshot._verify_expected_file
        file_checks = 0
        swapped = False
        timed_out = False

        def swap_then_verify(*args: object, **kwargs: object) -> None:
            nonlocal file_checks, swapped
            file_checks += 1
            if file_checks == 8:
                snapshot_file = self.scratch / "rick" / "SOUL.md"
                snapshot_file.unlink()
                os.mkfifo(snapshot_file)
                swapped = True
            original_verify_file(*args, **kwargs)

        def stop_blocking(_signum: int, _frame: object) -> None:
            nonlocal timed_out
            timed_out = True
            raise TimeoutError("final snapshot FIFO open blocked")

        previous = signal.signal(signal.SIGALRM, stop_blocking)
        started = time.monotonic()
        signal.setitimer(signal.ITIMER_REAL, 0.5)
        try:
            with mock.patch.object(
                profile_snapshot, "_verify_expected_file", side_effect=swap_then_verify
            ):
                with self.assertRaises(ProfileSnapshotError) as caught:
                    prepare_profile_snapshots(
                        self.manifest(self.profile("rick")),
                        self.scratch,
                        allow_missing=False,
                    )
        finally:
            signal.setitimer(signal.ITIMER_REAL, 0)
            signal.signal(signal.SIGALRM, previous)

        self.assertTrue(swapped)
        self.assertFalse(timed_out, "final snapshot FIFO open blocked")
        self.assertLess(time.monotonic() - started, 0.5)
        self.assertEqual(caught.exception.category, "cleanup_failed")
        self.assertEqual(str(caught.exception), "profile snapshot rejected (cleanup_failed)")

    def test_control_files_are_registered_before_post_write_verification(self) -> None:
        for index, control in enumerate(("distribution.yaml", ".gitignore")):
            with self.subTest(control=control):
                name = f"controlrace{index}"
                home = self.write_profile(name, ["SOUL.md"])
                (home / "SOUL.md").write_text("safe\n", encoding="utf-8")
                scratch = self.root / f"control-race-{index}"
                scratch.mkdir(mode=0o700)
                replacement = self.root / f"control-replacement-{index}"
                original_verify = profile_snapshot._verify_destination_descriptor
                replacement_status: os.stat_result | None = None
                replacement_payload: bytes | None = None
                expected_inode: int | None = None
                replacements = 0

                def replace_then_verify(
                    parent_fd: int,
                    candidate: str,
                    descriptor: int,
                    mode: int,
                    size: int,
                ) -> os.stat_result:
                    nonlocal expected_inode, replacement_payload, replacement_status, replacements
                    if candidate == control:
                        self.assertEqual(replacements, 0)
                        expected_inode = os.fstat(descriptor).st_ino
                        replacement_payload = b"R" * size
                        replacement.write_bytes(replacement_payload)
                        replacement.chmod(mode)
                        replacement_status = replacement.stat()
                        os.replace(replacement, scratch / name / candidate)
                        replacements += 1
                    return original_verify(
                        parent_fd, candidate, descriptor, mode, size
                    )

                with mock.patch.object(
                    profile_snapshot,
                    "_verify_destination_descriptor",
                    side_effect=replace_then_verify,
                ):
                    with self.assertRaises(ProfileSnapshotError) as caught:
                        prepare_profile_snapshots(
                            self.manifest(self.profile(name)),
                            scratch,
                            allow_missing=False,
                        )

                self.assertEqual(replacements, 1)
                self.assertIsNotNone(expected_inode)
                self.assertIsNotNone(replacement_payload)
                self.assertIsNotNone(replacement_status)
                assert replacement_payload is not None
                assert replacement_status is not None
                retained = scratch / name / control
                self.assertEqual(caught.exception.category, "cleanup_failed")
                self.assertEqual(retained.stat().st_ino, replacement_status.st_ino)
                self.assertEqual(retained.stat().st_mode, replacement_status.st_mode)
                self.assertEqual(retained.read_bytes(), replacement_payload)
                self.assertNotEqual(retained.stat().st_ino, expected_inode)
                self.assertEqual(
                    [path for path in (scratch / name).iterdir() if path.is_file()],
                    [retained],
                )

    def test_rejects_gitignore_destination_replacement_before_return(self) -> None:
        home = self.write_profile("rick", ["SOUL.md"])
        (home / "SOUL.md").write_text("safe\n", encoding="utf-8")
        replacement = self.root / "gitignore-replacement"
        replacement.write_bytes(b"*\n")
        replacement.chmod(0o644)
        replacement_inode = replacement.stat().st_ino
        original_write = profile_snapshot._write_private_file_at
        replaced = False

        def write_then_replace(
            parent_fd: int,
            name: str,
            content: bytes,
            mode: int,
            expected_files: list[object],
            fd_budget: object,
        ):
            nonlocal replaced
            result = original_write(
                parent_fd,
                name,
                content,
                mode,
                expected_files,
                fd_budget,
            )
            if name == ".gitignore" and not replaced:
                os.replace(replacement, self.scratch / "rick" / name)
                replaced = True
            return result

        with mock.patch("hermes_bootstrap.profile_snapshot._write_private_file_at", side_effect=write_then_replace):
            with self.assertRaises(ProfileSnapshotError) as caught:
                prepare_profile_snapshots(self.manifest(self.profile("rick")), self.scratch, allow_missing=False)
        self.assertTrue(replaced)
        self.assertEqual(caught.exception.category, "cleanup_failed")
        retained = self.scratch / "rick" / ".gitignore"
        self.assertEqual(retained.stat().st_ino, replacement_inode)
        self.assertEqual(retained.read_bytes(), b"*\n")

    def test_output_root_rename_cleanup_removes_exact_tree_and_preserves_replacement(self) -> None:
        home = self.write_profile("rick", ["SOUL.md"])
        content = b"rename-output-root\n"
        (home / "SOUL.md").write_bytes(content)
        moved = self.scratch / "retired-rick"
        replacement = self.scratch / "rick"
        original_write = profile_snapshot._write_descriptor
        swapped = False

        def write_then_swap(descriptor: int, chunk: bytes) -> None:
            nonlocal swapped
            original_write(descriptor, chunk)
            if chunk == content and not swapped:
                (self.scratch / "rick").rename(moved)
                replacement.mkdir(mode=0o700)
                (replacement / "marker").write_text("replacement\n", encoding="utf-8")
                swapped = True

        with mock.patch("hermes_bootstrap.profile_snapshot._write_descriptor", side_effect=write_then_swap):
            with self.assertRaises(ProfileSnapshotError) as caught:
                prepare_profile_snapshots(self.manifest(self.profile("rick")), self.scratch, allow_missing=False)
        self.assertTrue(swapped)
        self.assertEqual(caught.exception.category, "invalid_local_profile")
        self.assertFalse(moved.exists())
        self.assertEqual((replacement / "marker").read_text(encoding="utf-8"), "replacement\n")

    def test_output_root_cleanup_failure_is_redacted_and_surfaced(self) -> None:
        home = self.write_profile("rick", ["SOUL.md"])
        content = b"escape-output-root\n"
        (home / "SOUL.md").write_bytes(content)
        escaped = self.root / "escaped-rick"
        replacement = self.scratch / "rick"
        original_write = profile_snapshot._write_descriptor
        swapped = False

        def write_then_escape(descriptor: int, chunk: bytes) -> None:
            nonlocal swapped
            original_write(descriptor, chunk)
            if chunk == content and not swapped:
                (self.scratch / "rick").rename(escaped)
                replacement.mkdir(mode=0o700)
                (replacement / "marker").write_text("replacement\n", encoding="utf-8")
                swapped = True

        with mock.patch("hermes_bootstrap.profile_snapshot._write_descriptor", side_effect=write_then_escape):
            with self.assertRaises(ProfileSnapshotError) as caught:
                prepare_profile_snapshots(self.manifest(self.profile("rick")), self.scratch, allow_missing=False)
        self.assertTrue(swapped)
        self.assertEqual(caught.exception.category, "cleanup_failed")
        self.assertEqual((replacement / "marker").read_text(encoding="utf-8"), "replacement\n")
        self.assertTrue(escaped.is_dir())
        self.assertEqual(list(escaped.iterdir()), [])

    def test_output_root_swap_after_verification_preserves_replacement(self) -> None:
        home = self.write_profile("rick", ["SOUL.md"])
        (home / "SOUL.md").write_text("safe\n", encoding="utf-8")
        moved = self.scratch / "retired-rick"
        replacement = self.scratch / "rick"
        original_verify = profile_snapshot._verify_prepared_snapshot
        verify_calls = 0
        swapped = False

        def verify_then_swap(*args: object, **kwargs: object) -> None:
            nonlocal verify_calls, swapped
            original_verify(*args, **kwargs)
            verify_calls += 1
            if verify_calls == 2:
                replacement.rename(moved)
                replacement.mkdir(mode=0o700)
                (replacement / "marker").write_text("replacement\n", encoding="utf-8")
                swapped = True

        with mock.patch.object(
            profile_snapshot, "_verify_prepared_snapshot", side_effect=verify_then_swap
        ):
            with self.assertRaises(ProfileSnapshotError) as caught:
                prepare_profile_snapshots(
                    self.manifest(self.profile("rick")), self.scratch, allow_missing=False
                )

        self.assertTrue(swapped)
        self.assertEqual(verify_calls, 2)
        self.assertEqual(caught.exception.category, "invalid_local_profile")
        self.assertFalse(moved.exists())
        self.assertEqual((replacement / "marker").read_text(encoding="utf-8"), "replacement\n")

    def test_output_root_escape_after_verification_surfaces_cleanup_failure(self) -> None:
        home = self.write_profile("rick", ["SOUL.md"])
        (home / "SOUL.md").write_text("safe\n", encoding="utf-8")
        escaped = self.root / "escaped-after-verification"
        replacement = self.scratch / "rick"
        original_verify = profile_snapshot._verify_prepared_snapshot
        verify_calls = 0
        swapped = False

        def verify_then_escape(*args: object, **kwargs: object) -> None:
            nonlocal verify_calls, swapped
            original_verify(*args, **kwargs)
            verify_calls += 1
            if verify_calls == 2:
                replacement.rename(escaped)
                replacement.mkdir(mode=0o700)
                (replacement / "marker").write_text("replacement\n", encoding="utf-8")
                swapped = True

        with mock.patch.object(
            profile_snapshot, "_verify_prepared_snapshot", side_effect=verify_then_escape
        ):
            with self.assertRaises(ProfileSnapshotError) as caught:
                prepare_profile_snapshots(
                    self.manifest(self.profile("rick")), self.scratch, allow_missing=False
                )

        self.assertTrue(swapped)
        self.assertEqual(verify_calls, 2)
        self.assertEqual(caught.exception.category, "cleanup_failed")
        self.assertEqual((replacement / "marker").read_text(encoding="utf-8"), "replacement\n")
        self.assertTrue(escaped.is_dir())
        self.assertEqual(list(escaped.iterdir()), [])

    def test_cleanup_quarantine_never_overwrites_a_collision(self) -> None:
        home = self.write_profile("rick", ["SOUL.md"])
        (home / "SOUL.md").write_text("safe\n", encoding="utf-8")
        marker = b"quarantine-collision-survived\n"
        original_unused = profile_snapshot._unused_cleanup_name
        collision_created = False

        def create_collision(parent_fd: int) -> str:
            nonlocal collision_created
            candidate = original_unused(parent_fd)
            if not collision_created:
                descriptor = os.open(
                    candidate,
                    os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC,
                    0o600,
                    dir_fd=parent_fd,
                )
                try:
                    os.write(descriptor, marker)
                finally:
                    os.close(descriptor)
                collision_created = True
            return candidate

        with (
            mock.patch.object(
                profile_snapshot,
                "_final_attest_prepared_snapshot",
                side_effect=ValueError("force cleanup"),
            ) as final_attest,
            mock.patch.object(
                profile_snapshot, "_unused_cleanup_name", side_effect=create_collision
            ),
        ):
            with self.assertRaises(ProfileSnapshotError) as caught:
                prepare_profile_snapshots(
                    self.manifest(self.profile("rick")),
                    self.scratch,
                    allow_missing=False,
                )

        remaining = sorted(
            path.read_bytes() for path in self.scratch.rglob("*") if path.is_file()
        )
        self.assertTrue(collision_created)
        final_attest.assert_called_once()
        self.assertEqual(caught.exception.category, "cleanup_failed")
        self.assertEqual(remaining, [marker])

    def test_cleanup_replacement_immediately_before_delete_survives(self) -> None:
        home = self.write_profile("rick", ["SOUL.md"])
        (home / "SOUL.md").write_text("safe\n", encoding="utf-8")
        replacement = self.root / "pre-delete-replacement"
        marker = b"pre-delete-replacement-survived\n"
        replacement.write_bytes(marker)
        replacement_status = replacement.stat()
        escaped_expected = self.root / "escaped-pre-delete-expected"
        original_delete = profile_snapshot._delete_after_atomic_transfer
        delete_calls = 0
        replaced = False
        retained_name: str | None = None

        def replace_before_delete(
            parent_fd: int,
            name: str,
            descriptor: int,
            expected_identity: tuple[int, int],
            *,
            directory: bool,
            collided: bool,
        ) -> None:
            nonlocal delete_calls, replaced, retained_name
            delete_calls += 1
            if not directory and not replaced:
                source = profile_snapshot._descriptor_projection(parent_fd) / name
                source.rename(escaped_expected)
                replacement.rename(source)
                retained_name = name
                replaced = True
            original_delete(
                parent_fd,
                name,
                descriptor,
                expected_identity,
                directory=directory,
                collided=collided,
            )

        with (
            mock.patch.object(
                profile_snapshot,
                "_final_attest_prepared_snapshot",
                side_effect=ValueError("force cleanup"),
            ) as final_attest,
            mock.patch.object(
                profile_snapshot,
                "_delete_after_atomic_transfer",
                side_effect=replace_before_delete,
            ),
        ):
            with self.assertRaises(ProfileSnapshotError) as caught:
                prepare_profile_snapshots(
                    self.manifest(self.profile("rick")),
                    self.scratch,
                    allow_missing=False,
                )

        retained = [path for path in self.scratch.rglob("*") if path.is_file()]
        self.assertTrue(replaced)
        self.assertGreaterEqual(delete_calls, 1)
        final_attest.assert_called_once()
        self.assertEqual(caught.exception.category, "cleanup_failed")
        self.assertIsNotNone(retained_name)
        assert retained_name is not None
        retained_replacement = self.scratch / "rick" / retained_name
        self.assertTrue(retained_replacement.exists())
        self.assertEqual(len(retained), 1)
        self.assertEqual(retained[0], retained_replacement)
        self.assertEqual(retained[0].stat().st_ino, replacement_status.st_ino)
        self.assertEqual(retained[0].stat().st_mode, replacement_status.st_mode)
        self.assertEqual(retained[0].read_bytes(), marker)
        self.assertEqual(escaped_expected.read_bytes(), b"")

    def test_real_directory_ancestor_replacement_is_detected_before_a_snapshot_escapes(self) -> None:
        home = self.write_profile("rick", ["SOUL.md"])
        (home / "SOUL.md").write_text("safe\n", encoding="utf-8")
        profiles = home.parent
        moved = self.root / "moved-profiles"
        original_write = profile_snapshot._write_descriptor
        swapped = False

        def write_then_swap(descriptor: int, content: bytes) -> None:
            nonlocal swapped
            original_write(descriptor, content)
            if content == b"safe\n" and not swapped:
                profiles.rename(moved)
                profiles.mkdir()
                (profiles / "rick").mkdir()
                swapped = True

        with mock.patch("hermes_bootstrap.profile_snapshot._write_descriptor", side_effect=write_then_swap):
            with self.assertRaises(ProfileSnapshotError) as caught:
                prepare_profile_snapshots(self.manifest(self.profile("rick")), self.scratch, allow_missing=False)
        self.assertTrue(swapped)
        self.assertEqual(caught.exception.category, "invalid_local_profile")
        self.assertFalse((self.scratch / "rick").exists())

    def test_real_nested_directory_replacement_is_rejected_and_cleaned_up(self) -> None:
        home = self.write_profile("rick", ["assets"])
        nested = home / "assets" / "nested"
        nested.mkdir(parents=True)
        (nested / "avatar.png").write_bytes(b"nested-avatar")
        replacement = self.root / "replacement-assets"
        replacement.mkdir()
        (replacement / "replacement.png").write_bytes(b"replacement")
        original_write = profile_snapshot._write_descriptor
        replaced = False
        replace_calls = 0

        def write_then_replace_nested(directory: int, content: bytes) -> None:
            nonlocal replace_calls, replaced
            original_write(directory, content)
            if content == b"nested-avatar" and not replaced:
                os.replace(home / "assets", self.root / "stale-assets")
                os.replace(replacement, home / "assets")
                replace_calls += 1
                replaced = True

        with mock.patch("hermes_bootstrap.profile_snapshot._write_descriptor", side_effect=write_then_replace_nested):
            with self.assertRaises(ProfileSnapshotError) as caught:
                prepare_profile_snapshots(self.manifest(self.profile("rick")), self.scratch, allow_missing=False)
        self.assertTrue(replaced)
        self.assertEqual(replace_calls, 1)
        self.assertTrue((self.root / "stale-assets" / "nested" / "avatar.png").is_file())
        self.assertTrue((home / "assets" / "replacement.png").is_file())
        self.assertEqual(caught.exception.category, "invalid_local_profile")
        self.assertFalse((self.scratch / "rick").exists())

    def test_rejects_a_manifest_replaced_after_descriptor_read(self) -> None:
        home = self.write_profile("rick", ["SOUL.md"], description="original")
        (home / "SOUL.md").write_text("safe\n", encoding="utf-8")
        replacement = self.root / "replacement-manifest.yaml"
        replacement.write_text(
            yaml.safe_dump(
                {"name": "rick", "version": "0.1.0", "description": "replaced", "hermes_requires": ">=0.18.2", "distribution_owned": ["SOUL.md"]},
                sort_keys=False,
            ),
            encoding="utf-8",
        )
        original_read = profile_snapshot._read_regular
        source_stat = home.stat()
        replaced = False

        def read_then_replace(parent_fd: int, name: str):
            nonlocal replaced
            result = original_read(parent_fd, name)
            if name == "distribution.yaml" and os.fstat(parent_fd).st_ino == source_stat.st_ino and not replaced:
                replaced = True
                os.replace(replacement, home / "distribution.yaml")
            return result

        with mock.patch("hermes_bootstrap.profile_snapshot._read_regular", side_effect=read_then_replace):
            with self.assertRaises(ProfileSnapshotError) as caught:
                prepare_profile_snapshots(self.manifest(self.profile("rick")), self.scratch, allow_missing=False)
        self.assertTrue(replaced)
        self.assertEqual(caught.exception.category, "invalid_local_profile")
        self.assertFalse((self.scratch / "rick").exists())

    def test_rejects_private_manifest_replaced_during_hermes_validation(self) -> None:
        home = self.write_profile("rick", ["SOUL.md"], description="original")
        (home / "SOUL.md").write_text("safe\n", encoding="utf-8")
        replacement = self.root / "private-replacement.yaml"
        replacement_bytes = yaml.safe_dump(
            {"name": "rick", "version": "0.1.0", "description": "replaced", "hermes_requires": ">=0.18.2", "distribution_owned": ["SOUL.md"]},
            sort_keys=False,
        ).encode("utf-8")
        replacement.write_bytes(replacement_bytes)
        replacement_inode = replacement.stat().st_ino
        original_read = profile_snapshot.distributions._read_profile_manifest_at
        calls: list[bool] = []
        replaced = False

        def read_then_replace(root: Path, expected_name: str, *, require_sources: bool):
            nonlocal replaced
            calls.append(require_sources)
            result = original_read(root, expected_name, require_sources=require_sources)
            os.replace(replacement, root / "distribution.yaml")
            replaced = True
            return result

        with mock.patch.object(profile_snapshot.distributions, "_read_profile_manifest_at", side_effect=read_then_replace):
            with self.assertRaises(ProfileSnapshotError) as caught:
                prepare_profile_snapshots(self.manifest(self.profile("rick")), self.scratch, allow_missing=False)
        self.assertTrue(replaced)
        self.assertEqual(calls, [True])
        self.assertEqual(caught.exception.category, "cleanup_failed")
        retained = self.scratch / "rick" / "distribution.yaml"
        self.assertEqual(retained.stat().st_ino, replacement_inode)
        self.assertEqual(retained.read_bytes(), replacement_bytes)

    def test_rejects_transient_hermes_manifest_semantic_mismatch(self) -> None:
        alternate_values: tuple[tuple[str, object], ...] = (
            ("name", "alternate"),
            ("version", "0.2.0"),
            ("description", "alternate description"),
            ("hermes_requires", ">=0.18.1"),
            ("author", "Alternate Author"),
            ("license", "Apache-2.0"),
            (
                "env_requires",
                [
                    {
                        "name": "ALTERNATE_ENV",
                        "description": "alternate",
                        "required": True,
                    }
                ],
            ),
            ("distribution_owned", ["SOUL.md", "assets/avatar.png"]),
        )
        original_read = profile_snapshot.distributions._read_profile_manifest_at

        for index, (field, alternate_value) in enumerate(alternate_values):
            with self.subTest(field=field):
                name = f"semantic{index}"
                home = self.write_profile(
                    name,
                    ["SOUL.md", "assets"],
                    description="original description",
                    author="Original Author",
                    license="MIT",
                    env_requires=[
                        {
                            "name": "ORIGINAL_ENV",
                            "description": "original",
                            "required": False,
                        }
                    ],
                )
                (home / "SOUL.md").write_text("safe\n", encoding="utf-8")
                (home / "assets").mkdir()
                (home / "assets" / "avatar.png").write_bytes(b"avatar")
                scratch = self.root / f"semantic-scratch-{index}"
                scratch.mkdir(mode=0o700)
                alternate_payload: dict[str, object] = {
                    "name": name,
                    "version": "0.1.0",
                    "description": "original description",
                    "hermes_requires": ">=0.18.2",
                    "author": "Original Author",
                    "license": "MIT",
                    "env_requires": [
                        {
                            "name": "ORIGINAL_ENV",
                            "description": "original",
                            "required": False,
                        }
                    ],
                    "distribution_owned": ["SOUL.md", "assets"],
                }
                alternate_payload[field] = alternate_value
                alternate = yaml.safe_dump(
                    alternate_payload, sort_keys=False
                ).encode("utf-8")
                parser_returned = False
                alternate_replaced = False
                canonical_inode_restored = False
                parser_calls = 0
                require_sources_calls: list[bool] = []

                def read_alternate_then_restore(
                    root: Path, expected_name: str, *, require_sources: bool
                ):
                    nonlocal alternate_replaced, canonical_inode_restored, parser_calls, parser_returned
                    parser_calls += 1
                    require_sources_calls.append(require_sources)
                    manifest_path = root / "distribution.yaml"
                    canonical_inode = manifest_path.stat().st_ino
                    backup_path = root / f".canonical-{index}.yaml"
                    alternate_path = root / f".alternate-{index}.yaml"
                    alternate_path.write_bytes(alternate)
                    manifest_path.rename(backup_path)
                    os.replace(alternate_path, manifest_path)
                    alternate_replaced = manifest_path.read_bytes() == alternate
                    try:
                        parser_name = (
                            str(alternate_value) if field == "name" else expected_name
                        )
                        parsed = original_read(
                            root, parser_name, require_sources=require_sources
                        )
                        parser_returned = True
                    finally:
                        os.replace(backup_path, manifest_path)
                        canonical_inode_restored = (
                            manifest_path.stat().st_ino == canonical_inode
                        )
                    return parsed

                with mock.patch.object(
                    profile_snapshot.distributions,
                    "_read_profile_manifest_at",
                    side_effect=read_alternate_then_restore,
                ):
                    with self.assertRaises(ProfileSnapshotError) as caught:
                        prepare_profile_snapshots(
                            self.manifest(self.profile(name)),
                            scratch,
                            allow_missing=False,
                        )

                self.assertTrue(alternate_replaced)
                self.assertTrue(parser_returned)
                self.assertTrue(canonical_inode_restored)
                self.assertEqual(parser_calls, 1)
                self.assertEqual(require_sources_calls, [True])
                self.assertEqual(caught.exception.category, "invalid_local_profile")
                self.assertEqual(
                    str(caught.exception),
                    "profile snapshot rejected (invalid_local_profile)",
                )
                self.assertEqual(list(scratch.iterdir()), [])

    def test_rejects_incompatible_hermes_requirement(self) -> None:
        home = self.write_profile("rick", ["SOUL.md"])
        (home / "SOUL.md").write_text("safe\n", encoding="utf-8")
        (home / "distribution.yaml").write_text(
            yaml.safe_dump({"name": "rick", "version": "0.1.0", "hermes_requires": ">999.0.0", "distribution_owned": ["SOUL.md"]}),
            encoding="utf-8",
        )
        with self.assertRaises(ProfileSnapshotError):
            prepare_profile_snapshots(self.manifest(self.profile("rick")), self.scratch, allow_missing=False)


if __name__ == "__main__":
    unittest.main()
