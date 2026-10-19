"""Exercise literal source updates without fetching releases or invoking Nix."""

from __future__ import annotations

import sys
import tempfile
import unittest
from dataclasses import replace
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts/python"))

import update_darwin_packages as updater

ORCA_NIX = """{ stdenvNoCC, fetchurl, callPackage }:
let
  release = {
    version = "1.0.0";
    sources = {
      x86_64-linux = {
        url = "https://example.test/v1.0.0/orca-linux.AppImage";
        hash = "sha256-old-x86_64";
      };
      aarch64-darwin = {
        url = "https://example.test/v1.0.0/orca-macos-arm64.dmg";
        hash = "sha256-old-darwin";
      };
      aarch64-linux = {
        url = "https://example.test/v1.0.0/orca-linux-arm64.AppImage";
        hash = "sha256-old-aarch64";
      };
    };
  };
  system = stdenvNoCC.hostPlatform.system;
  source = release.sources.${system} or (throw "unsupported ${system}");
in
if stdenvNoCC.hostPlatform.isLinux then
  callPackage ./linux.nix { inherit source; inherit (release) version; }
else
  stdenvNoCC.mkDerivation {
    pname = "orca-editor";
    inherit (release) version;
    src = fetchurl source;
    installPhase = ''cp -R Orca.app "$out/Applications/"'';
  }
"""

DIA_NIX = """{ stdenvNoCC, fetchurl }:
stdenvNoCC.mkDerivation {
  pname = "dia-browser";
  version = "1.0.0";
  src = fetchurl {
    url = "https://example.test/Dia-1.0.0.zip";
    hash = "sha256-old-dia";
  };
  installPhase = ''cp -R Dia.app "$out/Applications/"'';
}
"""


def orca_sources() -> dict[str, dict[str, str]]:
    return {
        "aarch64-linux": {
            "url": "https://example.test/v2.0.0/orca-linux-arm64.AppImage",
            "hash": "sha256-new-aarch64",
        },
        "aarch64-darwin": {
            "url": "https://example.test/v2.0.0/orca-macos-arm64.dmg",
            "hash": "sha256-new-darwin",
        },
        "x86_64-linux": {
            "url": "https://example.test/v2.0.0/orca-linux.AppImage",
            "hash": "sha256-new-x86_64",
        },
    }


def orca_update() -> dict[str, object]:
    return {
        "package": "orca-editor",
        "status": "update-available",
        "version": "2.0.0",
        "url": "https://example.test/v2.0.0/orca-macos-arm64.dmg",
        "hash": "sha256-new-darwin",
        "sources": orca_sources(),
    }


class DarwinPackageUpdateTests(unittest.TestCase):
    def test_read_selects_darwin_when_linux_is_the_first_source(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "package.nix"
            path.write_text(ORCA_NIX, encoding="utf-8")
            self.assertEqual(
                updater.current_literals(path),
                (
                    "1.0.0",
                    "https://example.test/v1.0.0/orca-macos-arm64.dmg",
                    "sha256-old-darwin",
                ),
            )

    def test_apply_updates_all_sources_and_preserves_package_implementation(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "package.nix"
            path.write_text(ORCA_NIX, encoding="utf-8")
            profile = replace(updater.PROFILES["orca-editor"], derivation=path)
            with patch.dict(updater.PROFILES, {"orca-editor": profile}):
                updater.apply_updates([orca_update()])
            self.assertEqual(
                path.read_text(encoding="utf-8"),
                ORCA_NIX.replace("1.0.0", "2.0.0").replace(
                    "sha256-old-", "sha256-new-"
                ),
            )

    def test_single_source_dia_read_and_update_remain_supported(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "package.nix"
            path.write_text(DIA_NIX, encoding="utf-8")
            self.assertEqual(
                updater.current_literals(path),
                ("1.0.0", "https://example.test/Dia-1.0.0.zip", "sha256-old-dia"),
            )
            profile = replace(updater.PROFILES["dia-browser"], derivation=path)
            with patch.dict(updater.PROFILES, {"dia-browser": profile}):
                updater.apply_updates(
                    [
                        {
                            "package": "dia-browser",
                            "status": "update-available",
                            "version": "2.0.0",
                            "url": "https://example.test/Dia-2.0.0.zip",
                            "hash": "sha256-new-dia",
                        }
                    ]
                )
            self.assertEqual(
                path.read_text(encoding="utf-8"),
                DIA_NIX.replace("1.0.0", "2.0.0").replace(
                    "sha256-old-dia", "sha256-new-dia"
                ),
            )

    def test_invalid_supplied_sources_leave_the_file_unchanged(self) -> None:
        malformed_sources = (
            None,
            {
                "aarch64-darwin": {
                    "url": "https://example.test/new.dmg",
                    "hash": "sha256-new",
                }
            },
            {
                **orca_sources(),
                "x86_64-darwin": {
                    "url": "https://example.test/extra.dmg",
                    "hash": "sha256-extra",
                },
            },
            {
                **orca_sources(),
                "aarch64-linux": {"url": "https://example.test/new.AppImage"},
            },
            {
                **orca_sources(),
                "aarch64-linux": {
                    "url": '${builtins.abort "injected"}',
                    "hash": "sha256-new",
                },
            },
        )
        for sources in malformed_sources:
            with (
                self.subTest(sources=sources),
                tempfile.TemporaryDirectory() as directory,
            ):
                path = Path(directory) / "package.nix"
                path.write_text(ORCA_NIX, encoding="utf-8")
                update = orca_update()
                if sources is None:
                    del update["sources"]
                else:
                    update["sources"] = sources
                profile = replace(updater.PROFILES["orca-editor"], derivation=path)
                with (
                    patch.dict(updater.PROFILES, {"orca-editor": profile}),
                    self.assertRaises(ValueError),
                ):
                    updater.apply_updates([update])
                self.assertEqual(path.read_text(encoding="utf-8"), ORCA_NIX)

    def test_missing_duplicate_or_unexpected_nix_sources_are_rejected_before_write(
        self,
    ) -> None:
        source_block = """      aarch64-linux = {
        url = "https://example.test/v1.0.0/orca-linux-arm64.AppImage";
        hash = "sha256-old-aarch64";
      };
"""
        malformed_definitions = (
            ORCA_NIX.replace(source_block, ""),
            ORCA_NIX.replace(source_block, source_block * 2),
            ORCA_NIX.replace("aarch64-linux =", "x86_64-darwin ="),
            ORCA_NIX.replace('        hash = "sha256-old-aarch64";\n', ""),
        )
        for original in malformed_definitions:
            with (
                self.subTest(original=original),
                tempfile.TemporaryDirectory() as directory,
            ):
                path = Path(directory) / "package.nix"
                path.write_text(original, encoding="utf-8")
                profile = replace(updater.PROFILES["orca-editor"], derivation=path)
                with (
                    patch.dict(updater.PROFILES, {"orca-editor": profile}),
                    self.assertRaises(ValueError),
                ):
                    updater.apply_updates([orca_update()])
                self.assertEqual(path.read_text(encoding="utf-8"), original)


if __name__ == "__main__":
    unittest.main()
