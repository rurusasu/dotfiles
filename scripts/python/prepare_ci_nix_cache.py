"""Export private CI build outputs and retain one confirmed cache generation."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
from pathlib import Path
from urllib.parse import urlencode

from prepare_wsl_nix_cache import query_public_paths


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
    metadata: dict[Path, tuple[str, Path]] = {}
    for narinfo in cache.glob("*.narinfo"):
        fields = dict(
            line.split(": ", 1)
            for line in narinfo.read_text().splitlines()
            if ": " in line
        )
        blob = cache / fields["URL"]
        if not blob.resolve().is_relative_to((cache / "nar").resolve()):
            raise ValueError(f"Invalid NAR location in {narinfo.name}")
        if not blob.is_file():
            raise ValueError(f"Missing NAR payload in {narinfo.name}")
        metadata[narinfo] = (fields["StorePath"], blob)
    private_blobs = {blob for path, blob in metadata.values() if path not in public}
    # Omit public metadata too: a normal substituter must never advertise a NAR
    # whose payload is absent. Public references resolve via the public cache.
    for narinfo, (path, blob) in metadata.items():
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
    commands.add_parser("prune")
    arguments = parser.parse_args()
    if arguments.command == "export":
        export_cache(arguments.cache.resolve(), arguments.max_size)
    elif arguments.command == "root":
        root_dependencies(arguments.roots.resolve())
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
