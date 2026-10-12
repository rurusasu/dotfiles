"""Remove public NAR payloads from a disposable WSL transport cache.

Keep closure metadata so `nix copy` can traverse references after WSL has
realised the public paths from its configured, signature-checked caches.
The persistent CI binary cache must remain complete and is not modified.
"""

from __future__ import annotations

import argparse
import subprocess
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from threading import Event

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
                    "nix-store",
                    "--store",
                    PUBLIC_CACHE,
                    "--check-validity",
                    "--print-invalid",
                    *batch,
                ],
                capture_output=True,
                text=True,
                check=False,
                timeout=60,
            )
        except subprocess.TimeoutExpired:
            unavailable.set()
            print(
                "::warning::Public cache query timed out; retaining unconfirmed payloads"
            )
            return set()
        if result.returncode:
            unavailable.set()
            print(
                f"::warning::Public cache query failed; retaining unconfirmed payloads: {result.stderr.strip()}"
            )
            return set()
        invalid = set(result.stdout.splitlines())
        if not invalid <= set(batch):
            raise ValueError("Unexpected public-cache validity response")
        return set(batch) - invalid

    # nix-store checks paths sequentially; separate clients overlap requests.
    batches = [paths[start : start + 32] for start in range(0, len(paths), 32)]
    with ThreadPoolExecutor(max_workers=16) as executor:
        return set().union(*executor.map(query_batch, batches))


def prepare_cache(cache: Path, root: str) -> set[str]:
    """Prune only payloads whose entire closure is available publicly."""
    closure_result = subprocess.run(
        ["nix", "path-info", "--recursive", root],
        check=True,
        capture_output=True,
        text=True,
    )
    closure = set(closure_result.stdout.splitlines())
    if root not in closure:
        raise ValueError("Nix did not return the complete WSL closure")

    metadata: dict[str, tuple[Path, set[str]]] = {}
    narinfos = list(cache.glob("*.narinfo"))
    for narinfo in narinfos:
        fields = dict(
            line.split(": ", 1)
            for line in narinfo.read_text().splitlines()
            if ": " in line
        )
        path = fields.get("StorePath", "")
        if path not in closure:
            continue
        blob = cache / fields["URL"]
        if not blob.resolve().is_relative_to((cache / "nar").resolve()):
            raise ValueError(f"Invalid NAR location in {narinfo.name}")
        if not blob.is_file():
            raise ValueError(f"Missing NAR payload for {path}")
        refs = {f"/nix/store/{ref}" for ref in fields.get("References", "").split()}
        if not refs <= closure:
            raise ValueError(f"Incomplete reference closure for {path}")
        metadata[path] = (blob, refs)
    if set(metadata) != closure:
        raise ValueError("WSL transport cache is missing closure metadata")

    public = query_public_paths(sorted(closure))

    # Prefetching must work before importing any private payload. A public
    # path referencing a private path therefore stays in the artifact too.
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
    # Persistent caches can contain older systems; transfer only this closure.
    closure_hashes = {Path(path).name.split("-", 1)[0] for path in closure}
    for narinfo in narinfos:
        if narinfo.stem not in closure_hashes:
            narinfo.unlink()
    (cache / "public-paths.txt").write_text(
        "".join(f"{path}\n" for path in sorted(public))
    )
    print(
        f"WSL cache: {len(closure)} paths, {len(public)} public, {removed_bytes:,} payload bytes omitted"
    )
    return public


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("cache", type=Path)
    parser.add_argument("system_path")
    arguments = parser.parse_args()
    prepare_cache(arguments.cache, arguments.system_path)


if __name__ == "__main__":
    main()
