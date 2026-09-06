#!/usr/bin/env python3
"""Update reviewed custom Darwin derivations and test nixpkgs candidates.

The updater is intentionally conservative.  It only edits version, URL, and
hash literals in a known derivation, and it never changes a provider mapping
unless the candidate was evaluated, built, and identity-checked successfully.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import tempfile
import urllib.request
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable


ROOT = Path(__file__).resolve().parents[2]
REGISTRY_PATH = ROOT / "nix" / "packages" / "darwin-provider-candidates.nix"
DERIVATIONS = {
    "dia-browser": ROOT / "nix" / "packages" / "dia-browser" / "default.nix",
    "orca-editor": ROOT / "nix" / "packages" / "orca-editor" / "default.nix",
    "hammerspoon": ROOT / "nix" / "packages" / "hammerspoon" / "default.nix",
    "docker-desktop": ROOT / "nix" / "packages" / "docker-desktop" / "default.nix",
}


@dataclass(frozen=True)
class RegistryEntry:
    source: str
    nix_attr: str | None
    candidates: tuple[str, ...]


@dataclass(frozen=True)
class Candidate:
    package_id: str
    nix_attr: str


@dataclass(frozen=True)
class PromotionResult:
    entry: RegistryEntry
    promoted: bool
    reason: str | None = None
    nix_attr: str | None = None


@dataclass(frozen=True)
class Release:
    version: str
    url: str


@dataclass(frozen=True)
class PackageProfile:
    package_id: str
    feed_url: str
    derivation: Path
    parse_release: Callable[[bytes], Release | None]


def load_candidate_registry(path: Path = REGISTRY_PATH) -> dict[str, RegistryEntry]:
    """Parse the deliberately small Nix registry without evaluating arbitrary Nix."""
    text = path.read_text(encoding="utf-8")
    pattern = re.compile(
        r"(?ms)^\s*(?P<name>[A-Za-z0-9_-]+)\s*=\s*\{\s*"
        r"source\s*=\s*\"(?P<source>[^\"]+)\";\s*"
        r"nixAttr\s*=\s*(?P<nix_attr>null|\"[^\"]+\")\s*;\s*"
        r"candidates\s*=\s*\[(?P<candidates>.*?)\];\s*\};"
    )
    entries: dict[str, RegistryEntry] = {}
    for match in pattern.finditer(text):
        candidates = tuple(re.findall(r'"([^"\\]+)"', match.group("candidates")))
        nix_attr = match.group("nix_attr")
        entries[match.group("name")] = RegistryEntry(
            source=match.group("source"),
            nix_attr=None if nix_attr == "null" else nix_attr[1:-1],
            candidates=candidates,
        )
    if not entries:
        raise ValueError(f"no candidate entries found in {path}")
    return entries


def update_derivation_literals(
    text: str, *, version: str, url: str, hash_value: str
) -> str:
    """Replace exactly the three source literals in a custom derivation."""
    replacements = (
        (r'(?m)^(\s*version\s*=\s*)"[^"]+";', f'\\1"{version}";'),
        (r'(?m)^(\s*url\s*=\s*)"[^"]+";', f'\\1"{url}";'),
        (r'(?m)^(\s*hash\s*=\s*)"[^"]+";', f'\\1"{hash_value}";'),
    )
    updated = text
    for pattern, replacement in replacements:
        updated, count = re.subn(pattern, replacement, updated, count=1)
        if count != 1:
            raise ValueError(f"expected one literal matching {pattern!r}")
    return updated


def update_registry_entry(text: str, package_id: str, *, source: str, nix_attr: str) -> str:
    """Update only one registry record after a successful promotion."""
    entry = re.compile(
        rf"(?ms)(^\s*{re.escape(package_id)}\s*=\s*\{{.*?^\s*\}};)"
    )
    match = entry.search(text)
    if match is None:
        raise ValueError(f"candidate registry entry is missing: {package_id}")
    block = match.group(1)
    block, source_count = re.subn(
        r'(?m)^(\s*source\s*=\s*)"[^"]+";',
        rf'\1"{source}";',
        block,
        count=1,
    )
    block, attr_count = re.subn(
        r'(?m)^(\s*nixAttr\s*=\s*)(?:null|"[^"]+");',
        rf'\1"{nix_attr}";',
        block,
        count=1,
    )
    if source_count != 1 or attr_count != 1:
        raise ValueError(f"candidate registry entry is malformed: {package_id}")
    return text[: match.start(1)] + block + text[match.end(1) :]


def write_report(path: Path, report: dict[str, Any]) -> None:
    """Write a stable report, preserving bytes when its content is unchanged."""
    content = json.dumps(report, indent=2, sort_keys=False) + "\n"
    if path.exists() and path.read_bytes() == content.encode("utf-8"):
        return
    path.write_text(content, encoding="utf-8")


class NixRunner:
    """Small subprocess boundary used by the updater and its unit tests."""

    def __init__(
        self,
        *,
        repository: Path = ROOT,
        package_ids: dict[str, str] | None = None,
        identities: dict[str, dict[str, Any]] | None = None,
    ) -> None:
        self.repository = repository
        self.package_ids = package_ids or {}
        self.identities = identities or {}
        self.realized_paths: dict[str, Path] = {}

    def evaluate_candidate(self, nix_attr: str) -> None:
        self._run(["nix", "eval", "--impure", "--no-write-lock-file", "--expr", self._candidate_expr(nix_attr)])

    def build_candidate(self, nix_attr: str) -> None:
        result = subprocess.run(
            [
                "nix",
                "build",
                "--impure",
                "--no-write-lock-file",
                "--no-link",
                "--print-out-paths",
                "--expr",
                self._candidate_expr(nix_attr),
            ],
            cwd=self.repository,
            check=True,
            capture_output=True,
            text=True,
        )
        paths = result.stdout.splitlines()
        if not paths:
            raise RuntimeError(f"nix build returned no store path for {nix_attr}")
        self.realized_paths[nix_attr] = Path(paths[-1])

    def verify_identity(self, nix_attr: str) -> None:
        metadata = subprocess.run(
            [
                "nix",
                "eval",
                "--impure",
                "--no-write-lock-file",
                "--json",
                "--expr",
                self._identity_expr(nix_attr),
            ],
            cwd=self.repository,
            check=True,
            capture_output=True,
            text=True,
        )
        expected = self.identities.get(nix_attr, {})
        actual = json.loads(metadata.stdout)
        if expected.get("homepage") and actual.get("homepage") != expected["homepage"]:
            raise RuntimeError(
                f"homepage mismatch for {nix_attr}: expected {expected['homepage']}, got {actual.get('homepage')}"
            )

        package_id = self.package_ids.get(nix_attr, nix_attr)
        store_path = self.realized_paths.get(nix_attr)
        if store_path is None:
            raise RuntimeError(f"candidate was not realized before identity check: {nix_attr}")
        support = {
            package_id: {
                "darwin": {
                    "provider": "nix",
                    "source": "nixpkgs",
                    "identity": expected,
                }
            }
        }
        with tempfile.TemporaryDirectory(prefix="darwin-provider-verify-") as directory:
            support_json = Path(directory) / "support.json"
            support_json.write_text(json.dumps(support), encoding="utf-8")
            self._run(
                [
                    "bash",
                    "scripts/sh/verify-darwin-package.sh",
                    "--support-json",
                    str(support_json),
                    "--id",
                    package_id,
                    "--store-path",
                    str(store_path),
                ]
            )

    @staticmethod
    def _candidate_expr(nix_attr: str) -> str:
        return (
            "let flake = builtins.getFlake (toString ./.); "
            "pkgs = import flake.inputs.nixpkgs { system = \"aarch64-darwin\"; "
            "config.allowUnfree = true; }; "
            f"in builtins.getAttr {json.dumps(nix_attr)} pkgs"
        )

    @staticmethod
    def _identity_expr(nix_attr: str) -> str:
        return (
            "let flake = builtins.getFlake (toString ./.); "
            "pkgs = import flake.inputs.nixpkgs { system = \"aarch64-darwin\"; "
            "config.allowUnfree = true; }; "
            f"p = builtins.getAttr {json.dumps(nix_attr)} pkgs; "
            "in { homepage = p.meta.homepage or null; mainProgram = p.meta.mainProgram or null; }"
        )

    def _run(self, command: list[str]) -> None:
        subprocess.run(command, cwd=self.repository, check=True)


class RecordingNixRunner:
    """Deterministic runner used to test candidate selection and failure safety."""

    def __init__(self, build_error: str | None = None) -> None:
        self.evaluated: list[str] = []
        self.build_error = build_error

    def evaluate_candidate(self, nix_attr: str) -> None:
        self.evaluated.append(nix_attr)

    def build_candidate(self, nix_attr: str) -> None:
        if self.build_error:
            raise RuntimeError(self.build_error)

    def verify_identity(self, nix_attr: str) -> None:
        if self.build_error:
            raise RuntimeError(self.build_error)


def evaluate_candidates(
    candidates: dict[str, Candidate], runner: Any
) -> dict[str, bool]:
    """Evaluate only the explicit candidate mapping supplied by the caller."""
    result: dict[str, bool] = {}
    for package_id, candidate in candidates.items():
        runner.evaluate_candidate(candidate.nix_attr)
        result[package_id] = True
    return result


def try_promote(
    package_id: str,
    current: RegistryEntry,
    nix_attr: str,
    runner: Any,
) -> PromotionResult:
    """Promote only after all candidate checks succeed; retain custom on failure."""
    try:
        runner.evaluate_candidate(nix_attr)
        runner.build_candidate(nix_attr)
        runner.verify_identity(nix_attr)
    except (
        OSError,
        RuntimeError,
        ValueError,
        subprocess.CalledProcessError,
        subprocess.TimeoutExpired,
    ) as error:
        return PromotionResult(current, False, str(error), None)
    return PromotionResult(
        RegistryEntry("nixpkgs", nix_attr, current.candidates),
        True,
        None,
        nix_attr,
    )


def promote_candidates(
    registry: dict[str, RegistryEntry], package_ids: list[str], runner: Any
) -> dict[str, PromotionResult]:
    """Try only the explicitly listed candidates and return every decision."""
    results: dict[str, PromotionResult] = {}
    for package_id in package_ids:
        entry = registry[package_id]
        if entry.source != "custom":
            continue
        result = PromotionResult(entry, False, "no candidate passed")
        for candidate in entry.candidates:
            result = try_promote(package_id, entry, candidate, runner)
            if result.promoted:
                break
        results[package_id] = result
    return results


def _json_release(payload: bytes, *, arm64: bool = True) -> Release | None:
    data = json.loads(payload.decode("utf-8"))
    tag = str(data.get("tag_name", data.get("version", ""))).lstrip("v")
    assets = data.get("assets", [])
    urls = [asset.get("browser_download_url", "") for asset in assets]
    return _choose_release(tag, urls, arm64=arm64)


def _appcast_release(payload: bytes) -> Release | None:
    data = json.loads(payload.decode("utf-8"))
    items = data if isinstance(data, list) else data.get("updates", data.get("items", []))
    if isinstance(items, dict):
        items = [items]
    for item in items:
        if not isinstance(item, dict):
            continue
        version = str(item.get("version", item.get("shortVersionString", ""))).lstrip("v")
        url = str(item.get("url", item.get("download_url", "")))
        chosen = _choose_release(version, [url], arm64=True)
        if chosen:
            return chosen
    return None


def _dia_release(payload: bytes) -> Release | None:
    root = ET.fromstring(payload)
    urls = [element.attrib.get("url", "") for element in root.iter()]
    urls.extend(element.text or "" for element in root.iter() if element.text)
    for url in urls:
        match = re.search(r"Dia-([0-9][0-9A-Za-z.-]+)\.zip", url)
        if match:
            return Release(match.group(1), url)
    return None


def _choose_release(version: str, urls: list[str], *, arm64: bool) -> Release | None:
    if not version:
        return None
    usable = [url for url in urls if re.search(r"\.(?:zip|dmg)(?:\?.*)?$", url, re.I)]
    if arm64:
        arm = [url for url in usable if re.search(r"arm64|aarch64|apple-silicon", url, re.I)]
        if arm:
            usable = arm
    return Release(version, usable[0]) if usable else None


PROFILES = {
    "dia-browser": PackageProfile(
        "dia-browser",
        "https://releases.diabrowser.com/BoostBrowser-updates.xml",
        DERIVATIONS["dia-browser"],
        _dia_release,
    ),
    "hammerspoon": PackageProfile(
        "hammerspoon",
        "https://api.github.com/repos/Hammerspoon/hammerspoon/releases/latest",
        DERIVATIONS["hammerspoon"],
        lambda payload: _json_release(payload, arm64=True),
    ),
    "orca-editor": PackageProfile(
        "orca-editor",
        "https://api.github.com/repos/stablyai/orca/releases/latest",
        DERIVATIONS["orca-editor"],
        lambda payload: _json_release(payload, arm64=True),
    ),
    "docker-desktop": PackageProfile(
        "docker-desktop",
        "https://desktop.docker.com/mac/main/arm64/appcast.json",
        DERIVATIONS["docker-desktop"],
        _appcast_release,
    ),
}

IDENTITIES = {
    "dia-browser": {
        "homepage": "https://www.diabrowser.com/",
        "appName": "Dia.app",
        "bundleId": "company.thebrowser.dia",
        "executable": "Dia",
    },
    "orca-editor": {
        "homepage": "https://onorca.dev/",
        "appName": "Orca.app",
        "bundleId": "com.stablyai.orca",
        "executable": "Orca",
    },
    "hammerspoon": {
        "homepage": "https://www.hammerspoon.org/",
        "appName": "Hammerspoon.app",
        "bundleId": "org.hammerspoon.Hammerspoon",
        "executable": "Hammerspoon",
    },
    "docker-desktop": {
        "homepage": "https://www.docker.com/products/docker-desktop/",
        "appName": "Docker.app",
        "bundleId": "com.docker.docker",
        "executable": "com.docker.backend",
    },
}


def fetch(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": "dotfiles-darwin-updater"})
    with urllib.request.urlopen(request, timeout=30) as response:
        return response.read()


def prefetch_hash(url: str) -> str:
    result = subprocess.run(
        ["nix", "store", "prefetch-file", "--json", url],
        check=True,
        capture_output=True,
        text=True,
        timeout=300,
    )
    data = json.loads(result.stdout)
    hash_value = str(data.get("hash", ""))
    if not hash_value:
        raise ValueError(f"nix store prefetch returned no hash for {url}")
    return hash_value


def current_literals(path: Path) -> tuple[str, str, str]:
    text = path.read_text(encoding="utf-8")
    values = []
    for field in ("version", "url", "hash"):
        match = re.search(rf"(?m)^\s*{field}\s*=\s*\"([^\"]+)\";", text)
        if not match:
            raise ValueError(f"missing {field} in {path}")
        values.append(match.group(1))
    return tuple(values)  # type: ignore[return-value]


def collect_updates(
    package_ids: list[str], *, fetcher: Callable[[str], bytes] = fetch
) -> list[dict[str, str]]:
    updates: list[dict[str, str]] = []
    for package_id in package_ids:
        profile = PROFILES[package_id]
        version, old_url, old_hash = current_literals(profile.derivation)
        try:
            release = profile.parse_release(fetcher(profile.feed_url))
        except (OSError, ET.ParseError, json.JSONDecodeError) as error:
            updates.append({"package": package_id, "status": "error", "reason": str(error)})
            continue
        if release is None or release.version == version:
            continue
        try:
            hash_value = prefetch_hash(release.url)
        except (
            OSError,
            subprocess.CalledProcessError,
            subprocess.TimeoutExpired,
            json.JSONDecodeError,
            ValueError,
        ) as error:
            updates.append({"package": package_id, "status": "error", "reason": str(error)})
            continue
        updates.append(
            {
                "package": package_id,
                "status": "update-available",
                "version": release.version,
                "url": release.url,
                "hash": hash_value,
                "previous_version": version,
                "previous_url": old_url,
                "previous_hash": old_hash,
            }
        )
    return updates


def apply_updates(updates: list[dict[str, str]]) -> None:
    for update in updates:
        if update.get("status") != "update-available":
            continue
        path = DERIVATIONS[update["package"]]
        original = path.read_text(encoding="utf-8")
        updated = update_derivation_literals(
            original,
            version=update["version"],
            url=update["url"],
            hash_value=update["hash"],
        )
        if updated != original:
            path.write_text(updated, encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true", help="report changes without writing derivations")
    mode.add_argument("--write", action="store_true", help="apply safe derivation literal updates")
    parser.add_argument("--package", dest="packages", action="append", choices=sorted(PROFILES))
    parser.add_argument("--promote", action="store_true", help="verify explicit nixpkgs candidates")
    parser.add_argument("--output", type=Path, default=ROOT / "darwin-package-update.json")
    args = parser.parse_args(argv)

    package_ids = args.packages or list(PROFILES)
    registry = load_candidate_registry()
    updates = collect_updates(package_ids)
    promotion_results = (
        promote_candidates(
            registry,
            package_ids,
            NixRunner(
                package_ids={package_id: package_id for package_id in PROFILES},
                identities=IDENTITIES,
            ),
        )
        if args.promote
        else {}
    )
    promotions = [
        {
            "package": package_id,
            "status": "promoted" if result.promoted else "retained-custom",
            **({"nixAttr": result.nix_attr} if result.promoted else {}),
            **({"reason": result.reason} if result.reason else {}),
        }
        for package_id, result in promotion_results.items()
    ]
    report: dict[str, Any] = {"updates": updates, "promotions": promotions}
    if args.write:
        apply_updates(updates)
        if promotion_results:
            registry_text = REGISTRY_PATH.read_text(encoding="utf-8")
            for package_id, result in promotion_results.items():
                if result.promoted and result.nix_attr:
                    registry_text = update_registry_entry(
                        registry_text,
                        package_id,
                        source="nixpkgs",
                        nix_attr=result.nix_attr,
                    )
            REGISTRY_PATH.write_text(registry_text, encoding="utf-8")
    write_report(args.output, report)
    print(json.dumps(report, indent=2))
    # Loading the registry here makes an invalid or accidentally expanded
    # registry fail before a scheduled job can create a pull request.
    if set(registry) != set(PROFILES):
        raise ValueError("candidate registry and updater profiles differ")
    return 0


if __name__ == "__main__":
    sys.exit(main())
