"""Prepare private CI caches and WSL transport."""

from __future__ import annotations

import argparse
import base64
import hashlib
import heapq
import json
import os
import selectors
import shutil
import subprocess
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from threading import Event

ARCHIVE_RESERVE = 16 * 1024 * 1024
DISK_RESERVE = 64 * 1024 * 1024


def public_caches() -> list[str]:
    """Use configured remote substituters, never the restored optional cache."""
    result = subprocess.run(
        ["nix", "config", "show", "substituters"],
        check=True, capture_output=True, text=True,
    )
    return list(dict.fromkeys(
        cache for cache in result.stdout.split()
        if cache.startswith(("https://", "http://"))
    ))


def query_public_paths(paths: list[str]) -> set[str]:
    """Query all remote caches; an outage keeps unconfirmed payloads private."""
    caches = public_caches()
    unavailable = {cache: Event() for cache in caches}

    def query_batch(batch: list[str]) -> set[str]:
        missing = set(batch)
        for cache in caches:
            if not missing or unavailable[cache].is_set():
                continue
            try:
                result = subprocess.run(
                    ["nix-store", "--store", cache, "--check-validity", "--print-invalid", *sorted(missing)],
                    capture_output=True, text=True, check=True, timeout=60,
                )
            except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
                unavailable[cache].set()
                print("::warning::A remote cache query failed; retaining unconfirmed payloads")
                continue
            invalid = set(result.stdout.splitlines())
            if not invalid <= missing:
                raise ValueError("Unexpected public-cache validity response")
            missing = invalid
        return set(batch) - missing

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


def path_metadata(paths: list[str]) -> dict[str, dict]:
    """Read realised paths without exporting their reference closures."""
    if not paths:
        return {}
    result = subprocess.run(
        ["nix", "path-info", "--json", "--stdin"],
        input="".join(f"{path}\n" for path in paths),
        capture_output=True, text=True, check=True,
    )
    metadata = json.loads(result.stdout)
    # Nix returns a path-keyed object; Lix returns a list of path records.
    if isinstance(metadata, dict):
        records = {path: {**entry, "path": path} for path, entry in metadata.items()}
    else:
        records = {entry["path"]: entry for entry in metadata}
    if set(records) != set(paths):
        raise ValueError("Nix returned incomplete path metadata")
    for path, entry in records.items():
        if entry.get("narSize", -1) < 0 or not entry.get("narHash"):
            raise ValueError(f"Invalid NAR metadata for {path}")
    return records


def closed_public_paths(public: set[str], metadata: dict[str, dict]) -> set[str]:
    """Remote roots are public only when all transitive references are too."""
    while True:
        closed = {
            path for path in public
            if set(metadata[path].get("references", [])) <= public
        }
        if closed == public:
            return closed
        public = closed


def narinfo(entry: dict, filename: str, size: int, digest: str) -> str:
    """Describe one complete payload; references may resolve in remote caches."""
    lines = [
        f"StorePath: {entry['path']}", f"URL: nar/{filename}",
        "Compression: zstd", f"FileHash: sha256-{digest}", f"FileSize: {size}",
        f"NarHash: {entry['narHash']}", f"NarSize: {entry['narSize']}",
        "References: " + " ".join(sorted(Path(ref).name for ref in entry.get("references", []))),
    ]
    if entry.get("deriver"):
        lines.append(f"Deriver: {Path(entry['deriver']).name}")
    if entry.get("ca"):
        lines.append(f"CA: {entry['ca']}")
    return "\n".join(lines) + "\n"


def compress_path(path: str, destination: Path, maximum_bytes: int, timeout: int = 120) -> tuple[int, str, str] | None:
    """Stream one NAR, stopping before an oversized payload fills the disk."""
    processes = []
    try:
        with tempfile.TemporaryFile() as errors, destination.open("wb") as output:
            dump = subprocess.Popen(["nix-store", "--dump", path], stdout=subprocess.PIPE, stderr=errors)
            processes.append(dump)
            compressor = subprocess.Popen(
                ["zstd", "-q", "-T0", "-c"], stdin=dump.stdout, stdout=subprocess.PIPE, stderr=errors,
            )
            processes.append(compressor)
            dump.stdout.close()
            digest = hashlib.sha256()
            size = 0
            deadline = time.monotonic() + timeout
            with selectors.DefaultSelector() as selector:
                selector.register(compressor.stdout, selectors.EVENT_READ)
                while True:
                    remaining = deadline - time.monotonic()
                    if remaining <= 0 or not selector.select(remaining):
                        raise subprocess.TimeoutExpired(["nix-store", "--dump", path], timeout)
                    chunk = os.read(compressor.stdout.fileno(), min(1024 * 1024, maximum_bytes - size + 1))
                    if not chunk:
                        break
                    if size + len(chunk) > maximum_bytes:
                        return None
                    output.write(chunk)
                    digest.update(chunk)
                    size += len(chunk)
            compressor.stdout.close()
            for process in processes:
                status = process.wait(timeout=max(0.1, deadline - time.monotonic()))
                if status:
                    errors.seek(0)
                    raise RuntimeError(f"NAR export failed for {path}: " + errors.read(8192).decode("utf-8", errors="replace"))
            return size, digest.hexdigest(), base64.b64encode(digest.digest()).decode("ascii")
    finally:
        for process in processes:
            if process.poll() is None:
                process.kill()
        for process in processes:
            process.wait()
            if process.stdout is not None:
                process.stdout.close()


def export_entry(cache: Path, path: str, entry: dict, maximum_bytes: int, timeout: int = 120) -> tuple[Path, Path, int] | None:
    """Write one payload and narinfo within a byte limit; leave no partial entry."""
    overhead = len(narinfo(entry, "0" * 64 + ".nar.zst", 2**64 - 1, "0" * 44).encode())
    if maximum_bytes <= overhead:
        return None
    temporary = cache / "nar" / ".candidate"
    try:
        result = compress_path(path, temporary, maximum_bytes - overhead, timeout)
        if result is None:
            return None
        payload_size, hexadecimal, digest = result
        filename = hexadecimal + ".nar.zst"
        payload = cache / "nar" / filename
        record = narinfo(entry, filename, payload_size, digest)
        if payload.exists():
            temporary.unlink()
            payload_size = 0
        else:
            temporary.replace(payload)
        record_path = cache / (Path(path).name.split("-", 1)[0] + ".narinfo")
        record_path.write_text(record)
        return record_path, payload, payload_size + len(record.encode())
    finally:
        temporary.unlink(missing_ok=True)


def export_cache(cache: Path, maximum_size: int) -> None:
    """Save useful dependency-closed subsets rather than dropping a whole generation."""
    if maximum_size <= 0:
        raise ValueError("Cache size must be positive")
    cache.mkdir(parents=True, exist_ok=False)
    (cache / "nar").mkdir()
    (cache / "nix-cache-info").write_text("StoreDir: /nix/store\nWantMassQuery: 1\n")
    paths = store_paths()
    metadata = path_metadata(paths)
    public = closed_public_paths(query_public_paths(paths), metadata)
    private = set(paths) - public
    metadata = {path: metadata[path] for path in private}
    dependencies = {
        path: set(entry.get("references", [])) - public - {path}
        for path, entry in metadata.items()
    }
    dependents = {path: set() for path in private}
    for path, references in dependencies.items():
        for reference in references & private:
            dependents[reference].add(path)
    # Shared dependencies are useful even when the large application above them
    # cannot fit. A self reference is valid; other cycles are conservatively skipped.
    ready = []
    for path in private:
        if not dependencies[path]:
            heapq.heappush(ready, (-len(dependents[path]), -metadata[path]["narSize"], path))
    selected = set()
    size = (cache / "nix-cache-info").stat().st_size
    budget = maximum_size - ARCHIVE_RESERVE
    oversized = 0
    disk_limited = 0
    while ready:
        _, _, path = heapq.heappop(ready)
        entry = metadata[path]
        # Existing selected bytes also need an outer Actions archive. Reserve
        # room for that archive and twice the one pending compressed payload.
        capacity = budget - size
        free = shutil.disk_usage(cache).free
        disk_capacity = (free - DISK_RESERVE - size) // 2
        if capacity <= 0:
            break
        if disk_capacity <= 0:
            disk_limited += 1
            break
        limit = min(capacity, disk_capacity)
        result = export_entry(cache, path, entry, limit)
        if result is None:
            if disk_capacity < capacity:
                disk_limited += 1
                reason = "available disk space"
            else:
                oversized += 1
                reason = "remaining cache budget"
            print(f"CI cache skipped {path}: exceeds {limit:,}-byte {reason} (NAR {entry['narSize']:,} bytes)")
            continue
        _, _, added_bytes = result
        size += added_bytes
        selected.add(path)
        for dependent in dependents[path]:
            dependencies[dependent].discard(path)
            if not dependencies[dependent]:
                heapq.heappush(ready, (-len(dependents[dependent]), -metadata[dependent]["narSize"], dependent))
    # Never publish a root whose private dependencies were skipped for space.
    for path, _, _, refs in cache_entries(cache):
        if not refs <= public | selected:
            raise ValueError(f"Incomplete private reference closure for {path}")
    skipped = len(private) - len(selected)
    blocked = [path for path in sorted(private - selected) if dependencies[path]]
    for path in blocked[:20]:
        print(f"CI cache skipped {path}: {len(dependencies[path])} private references unavailable")
    if len(blocked) > 20:
        print(f"CI cache: {len(blocked) - 20} additional outputs blocked by skipped private references")
    print(
        f"CI cache: {len(selected)} selected / {len(private)} private / {len(paths)} paths, "
        f"{size:,} bytes; {skipped} skipped ({oversized} oversized, {disk_limited} disk-limited)"
    )
    if not selected:
        print("::warning::No dependency-closed private outputs fit; keeping the previous generation")
    with Path(os.environ["GITHUB_OUTPUT"]).open("a") as output:
        output.write(f"cacheable={str(bool(selected)).lower()}\n")
        output.write(f"space_constrained={str(bool(disk_limited)).lower()}\n")


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
    arguments = parser.parse_args()
    if arguments.command == "export":
        export_cache(arguments.cache.resolve(), arguments.max_size)
    elif arguments.command == "root":
        root_dependencies(arguments.roots.resolve())
    elif arguments.command == "transport":
        transport_cache(arguments.cache.resolve(), arguments.system_path)


if __name__ == "__main__":
    main()
