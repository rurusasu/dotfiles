"""Prepare CI caches and WSL transport, then retain confirmed cache generations."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from threading import Event
from urllib.parse import urlencode

PUBLIC_CACHE = "https://cache.nixos.org"


def query_public_paths(paths: list[str]) -> set[str]:
    """Bound parallel HTTP queries and retain payloads on a cache outage."""
    unavailable = Event()

    def query_batch(batch: list[str]) -> set[str]:
        if unavailable.is_set():
            return set()
        try:
            result = subprocess.run(
                [
                    "nix-store", "--store", PUBLIC_CACHE, "--check-validity", "--print-invalid", *batch,
                ],
                capture_output=True,
                text=True,
                check=True,
                timeout=60,
            )
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
            unavailable.set()
            print(f"::warning::Public cache query failed; retaining unconfirmed payloads: {error}")
            return set()
        invalid = set(result.stdout.splitlines())
        if not invalid <= set(batch):
            raise ValueError("Unexpected public-cache validity response")
        return set(batch) - invalid

    # nix-store checks paths sequentially; separate clients overlap requests.
    batches = [paths[start : start + 32] for start in range(0, len(paths), 32)]
    with ThreadPoolExecutor(max_workers=16) as executor:
        return set().union(*executor.map(query_batch, batches))


def cache_entries(cache: Path, closure: set[str] | None = None) -> list[tuple[str, Path, Path, set[str]]]:
    entries = []
    for narinfo in cache.glob("*.narinfo"):
        fields = dict(
            line.split(": ", 1) for line in narinfo.read_text().splitlines() if ": " in line
        )
        path = fields.get("StorePath", "")
        if closure is not None and path not in closure:
            continue
        if not path:
            raise ValueError(f"Missing store path in {narinfo.name}")
        blob = cache / fields["URL"]
        if not blob.resolve().is_relative_to((cache / "nar").resolve()):
            raise ValueError(f"Invalid NAR location in {narinfo.name}")
        if not blob.is_file():
            raise ValueError(f"Missing NAR payload in {narinfo.name}")
        refs = {f"/nix/store/{ref}" for ref in fields.get("References", "").split()}
        if closure is not None and not refs <= closure:
            raise ValueError(f"Incomplete reference closure for {path}")
        entries.append((path, narinfo, blob, refs))
    return entries


def store_paths() -> list[str]:
    """List realised paths without requesting builds of derivations."""
    result = subprocess.run(
        ["nix", "path-info", "--all"],
        check=True,
        capture_output=True,
        text=True,
    )
    return sorted(path for path in result.stdout.splitlines() if not path.endswith(".drv"))


def root_dependencies(roots: Path) -> None:
    """Keep private build dependencies alive through checks that trigger GC."""
    roots.mkdir(parents=True, exist_ok=False)
    paths = store_paths()
    private = sorted(set(paths) - query_public_paths(paths))
    # Batch roots to stay below platform command-line size limits.
    for start in range(0, len(private), 256):
        subprocess.run(
            [
                "nix-store",
                "--add-root",
                str(roots / f"root-{start}"),
                "--indirect",
                "--realise",
                *private[start : start + 256],
            ],
            stdout=subprocess.DEVNULL,
            check=True,
        )
    print(f"Protected {len(private)} private paths and their references from GC")


def export_cache(cache: Path, maximum_size: int) -> None:
    """Keep build dependencies as well as runtime outputs, without public NARs."""
    if maximum_size <= 0:
        raise ValueError("Cache size must be positive")
    cache.mkdir(parents=True, exist_ok=False)
    paths = store_paths()
    public = query_public_paths(paths)
    private = sorted(set(paths) - public)
    # Binary-cache exports require reference metadata to exist. Export the
    # private roots with their closure once, then remove confirmed public entries.
    subprocess.run(
        [
            "nix",
            "copy",
            "--stdin",
            "--to",
            f"{cache.as_uri()}?compression=zstd",
        ],
        input="".join(f"{path}\n" for path in private),
        text=True,
        check=True,
    )
    entries = cache_entries(cache)
    private_blobs = {blob for path, _, blob, _ in entries if path not in public}
    # Omit public metadata too: a normal substituter must never advertise a NAR
    # whose payload is absent. Public references resolve via the public cache.
    for path, narinfo, blob, _ in entries:
        if path in public:
            narinfo.unlink()
            if blob not in private_blobs and blob.exists():
                blob.unlink()
    size = sum(path.stat().st_size for path in cache.rglob("*") if path.is_file())
    # Leave room for the outer cache archive's metadata and framing.
    cacheable = size + 16 * 1024 * 1024 <= maximum_size
    print(f"CI cache: {len(private)} private / {len(paths)} paths, {size:,} bytes")
    if not cacheable:
        print("::warning::Private cache exceeds its budget; keeping the previous generation")
    with Path(os.environ["GITHUB_OUTPUT"]).open("a") as output:
        output.write(f"cacheable={str(cacheable).lower()}\n")


def transport_cache(cache: Path, root: str) -> None:
    """Prune disposable transport payloads only when their closure is public."""
    closure_result = subprocess.run(
        ["nix", "path-info", "--recursive", root],
        check=True,
        capture_output=True,
        text=True,
    )
    closure = set(closure_result.stdout.splitlines())
    if root not in closure:
        raise ValueError("Nix did not return the complete WSL closure")
    metadata = {path: (blob, refs) for path, _, blob, refs in cache_entries(cache, closure)}
    if set(metadata) != closure:
        raise ValueError("WSL transport cache is missing closure metadata")
    public = query_public_paths(sorted(closure))
    # Public prefetch must not require a private dependency that is still in the artifact.
    while True:
        closed = {path for path in public if metadata[path][1] <= public}
        if closed == public:
            break
        public = closed
    private_blobs = {blob for path, (blob, _) in metadata.items() if path not in public}
    removed_bytes = 0
    for blob in (cache / "nar").iterdir():
        if blob not in private_blobs:
            removed_bytes += blob.stat().st_size
            blob.unlink()
    # Transfer only this closure; the persistent cache remains untouched.
    closure_hashes = {Path(path).name.split("-", 1)[0] for path in closure}
    for narinfo in cache.glob("*.narinfo"):
        if narinfo.stem not in closure_hashes:
            narinfo.unlink()
    (cache / "public-paths.txt").write_text("".join(f"{path}\n" for path in sorted(public)))
    print(f"WSL cache: {len(closure)} paths, {len(public)} public, {removed_bytes:,} payload bytes omitted")


def prune_cache(key: str, prefix: str) -> None:
    """Delete older main caches only after the replacement is visible in GitHub."""
    if os.environ["GITHUB_REF"] != "refs/heads/main":
        raise ValueError("Only main may update shared caches")
    if not prefix.startswith("ci-nix-v2-") or not key.startswith(prefix):
        raise ValueError("Invalid CI cache namespace")
    base = f"{os.environ['GITHUB_API_URL']}/repos/{os.environ['GITHUB_REPOSITORY']}/actions/caches"

    api = ["gh", "api", "-H", "X-GitHub-Api-Version: 2022-11-28"]
    environment = os.environ | {"GH_TOKEN": os.environ["GITHUB_TOKEN"]}
    try:
        query = urlencode({"ref": "refs/heads/main", "key": prefix, "per_page": 100})
        result = subprocess.run(
            [*api, "--paginate", "--slurp", f"{base}?{query}"],
            capture_output=True,
            text=True,
            check=True,
            timeout=120,
            env=environment,
        )
        caches = [cache for page in json.loads(result.stdout) for cache in page["actions_caches"]]
        current = [cache for cache in caches if cache["key"] == key]
        if not current:
            print("::warning::New cache not confirmed; retaining previous generations")
            return
        newest = max(cache["created_at"] for cache in current)
        for cache in caches:
            if (
                cache["ref"] == "refs/heads/main"
                and cache["key"].startswith(prefix)
                and cache["key"] != key
                and cache["created_at"] < newest
            ):
                subprocess.run(
                    [*api, "--method", "DELETE", f"{base}/{cache['id']}"],
                    check=True,
                    timeout=30,
                    env=environment,
                )
                print(f"Removed older CI cache: {cache['key']}")
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired, OSError) as error:
        print(f"::warning::Cache cleanup unavailable; retaining caches: {error}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    export = commands.add_parser("export")
    export.add_argument("cache", type=Path)
    export.add_argument("--max-size", type=int, required=True)
    root = commands.add_parser("root")
    root.add_argument("roots", type=Path)
    transport = commands.add_parser("transport")
    transport.add_argument("cache", type=Path)
    transport.add_argument("system_path")
    commands.add_parser("prune")
    arguments = parser.parse_args()
    if arguments.command == "export":
        export_cache(arguments.cache.resolve(), arguments.max_size)
    elif arguments.command == "root":
        root_dependencies(arguments.roots.resolve())
    elif arguments.command == "transport":
        transport_cache(arguments.cache.resolve(), arguments.system_path)
    else:
        producers = json.loads(os.environ["CACHE_PRODUCERS"])
        for producer in producers.values():
            if producer["result"] != "success":
                continue
            outputs = producer["outputs"]
            if outputs.get("cache_key") and outputs.get("cache_prefix"):
                prune_cache(outputs["cache_key"], outputs["cache_prefix"])


if __name__ == "__main__":
    main()
