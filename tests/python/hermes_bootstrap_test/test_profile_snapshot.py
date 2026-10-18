from __future__ import annotations

import os
import socket
import sys
import tempfile
import unittest
from pathlib import Path

import yaml


BOOTSTRAP_ROOT = Path(__file__).resolve().parents[3] / "scripts" / "python"
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
            "default", "https://github.com/rurusasu/hermes-profile-alfred.git", "main", self.data_root, "root-distribution.yaml"
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


    def test_public_profile_config_only_strips_root_onepassword_block(self) -> None:
        content = (
            "settings:\n"
            "  secrets:\n"
            "    onepassword:\n"
            "      nested: true\n"
            "secrets:\n"
            "  onepassword:\n"
            "    root: true\n"
            "  retained: true\n"
        ).encode("utf-8")

        public = yaml.safe_load(profile_snapshot._public_profile_config(content))

        self.assertEqual(public["settings"]["secrets"]["onepassword"]["nested"], True)
        self.assertNotIn("onepassword", public["secrets"])
        self.assertEqual(public["secrets"]["retained"], True)
        inline = b"secrets: {onepassword: {root: true}, retained: true}\n"
        self.assertEqual(
            yaml.safe_load(profile_snapshot._public_profile_config(inline)),
            {"secrets": {"retained": True}},
        )
        home = self.write_profile("rick", ["config.yaml"])
        (home / "config.yaml").write_bytes(content)
        snapshot = prepare_profile_snapshots(
            self.manifest(self.profile("rick")), self.scratch
        )[0]
        self.assertEqual(yaml.safe_load((snapshot.root / "config.yaml").read_bytes()), public)
        self.assertEqual((home / "config.yaml").read_bytes(), content)


    def test_rejects_secret_candidates_before_publication(self) -> None:
        candidates = (
            b"ghp_abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN",
            b"github_pat_abcdefghijklmnopqrstuvwxyz",
            b"xoxb-valid",
            b"xapp-valid",
            b"AKIAIOSFODNN7EXAMPLE",
            b"eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.signature-value-long",
            b"sk-proj-abcdefghijklmnopqrstuvwxyz",
            b"hf_abcdefghijklmnopqrstuvwxyz",
            b"xai-abcdefghijklmnopqrstuvwxyz",
            b"1//abcdefghijklmnopqrstuvwxyz",
            b"-----BEGIN PRIVATE KEY-----",
            b"-----BEGIN ENCRYPTED PRIVATE KEY-----",
            b"-----BEGIN RSA PRIVATE KEY-----",
            b"-----BEGIN EC PRIVATE KEY-----",
            b"-----BEGIN DSA PRIVATE KEY-----",
            b"-----BEGIN OPENSSH PRIVATE KEY-----",
            b"-----BEGIN CERTIFICATE-----",
        )
        home = self.write_profile("rick", ["SOUL.md"])
        for candidate in candidates:
            with self.subTest(candidate=candidate[:8]):
                (home / "SOUL.md").write_bytes(b"example=" + candidate + b"\n")
                with self.assertRaises(ProfileSnapshotError) as caught:
                    prepare_profile_snapshots(
                        self.manifest(self.profile("rick")), self.scratch
                    )
                self.assertEqual(caught.exception.category, "invalid_local_profile")
                self.assertNotIn(candidate.decode("ascii"), str(caught.exception))
                self.assertEqual(list(self.scratch.iterdir()), [])


    def test_rejects_links_special_files_hardlinks_and_unreadable_files(self) -> None:
        home = self.write_profile("rick", ["assets"])
        (home / "assets").mkdir()
        (home / "assets" / "link").symlink_to("elsewhere")
        with self.assertRaises(ProfileSnapshotError):
            prepare_profile_snapshots(self.manifest(self.profile("rick")), self.scratch)

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
                    prepare_profile_snapshots(self.manifest(self.profile("rick")), self.scratch)
                if kind == "unreadable":
                    path.chmod(0o600)
                if kind == "hardlink":
                    (home / "extra-link").unlink()


if __name__ == "__main__":
    unittest.main()
