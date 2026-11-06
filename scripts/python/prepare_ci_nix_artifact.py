"""Transfer exact Nix build outputs between CI producers and E2E consumers.

This mandatory artifact is independent of the optional, bounded dependency cache.
The workflow must download the producer's exact artifact ID/digest; this manifest
detects corruption and mismatched jobs, rather than serving as a signature.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import re
import shlex
import shutil
import subprocess
import tarfile
import tempfile
from pathlib import Path

from prepare_ci_nix_cache import export_entry, query_public_paths

STORE_PATH = re.compile(r"/nix/store/[0-9abcdfghijklmnpqrsvwxyz]{32}-[A-Za-z0-9+._?=-]+\Z")
ROOT_NAME = re.compile(r"[a-z][a-z0-9-]*\Z")
SHA = re.compile(r"[0-9a-f]{40}\Z")
DIGEST = re.compile(r"[0-9a-f]{64}\Z")
TARGETS = ("darwin", "linux", "wsl")
NO_BUILD = ["--option", "max-jobs", "0", "--option", "builders", ""]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def unique_object(pairs: list[tuple[str, object]]) -> dict:
    result = {}
    for name, value in pairs:
        require(name not in result, f"Duplicate JSON key: {name}")
        result[name] = value
    return result


def read_json(path: Path) -> dict:
    value = json.loads(path.read_text(), object_pairs_hook=unique_object)
    require(isinstance(value, dict), "Expected a JSON object")
    return value


def roots_from_arguments(arguments: list[str]) -> dict[str, str]:
    roots = {}
    for argument in arguments:
        name, separator, path = argument.partition("=")
        require(bool(separator and ROOT_NAME.fullmatch(name)), f"Invalid root: {argument}")
        require(name not in roots, f"Duplicate root: {name}")
        require(bool(STORE_PATH.fullmatch(path)), f"Invalid store path: {path}")
        roots[name] = path
    require("source" in roots, "An immutable source root is required")
    return roots


def closure_metadata(roots: dict[str, str]) -> dict[str, dict]:
    result = subprocess.run(
        ["nix", "path-info", "--recursive", "--json", "--stdin"],
        input="".join(f"{path}\n" for path in sorted(set(roots.values()))),
        capture_output=True,
        text=True,
        check=True,
    )
    raw = json.loads(result.stdout, object_pairs_hook=unique_object)
    entries = ({**entry, "path": path} for path, entry in raw.items()) if isinstance(raw, dict) else raw
    require(isinstance(raw, (dict, list)), "Invalid Nix closure metadata")
    metadata = {}
    for entry in entries:
        path = entry["path"]
        require(path not in metadata, f"Duplicate closure path: {path}")
        metadata[path] = {
            "path": path,
            "narHash": entry["narHash"],
            "narSize": entry["narSize"],
            "references": sorted(entry["references"]),
        }
        if entry.get("ca"):
            metadata[path]["ca"] = entry["ca"]
    validate_closure(roots, metadata)
    return metadata


def validate_closure(roots: dict, metadata: dict) -> None:
    require(bool(roots) and "source" in roots, "An immutable source root is required")
    for name, path in roots.items():
        require(isinstance(name, str) and bool(ROOT_NAME.fullmatch(name)), "Invalid root name")
        require(isinstance(path, str) and bool(STORE_PATH.fullmatch(path)), "Invalid root path")
    require(set(roots.values()) <= metadata.keys(), "Missing root in closure")
    for path, entry in metadata.items():
        require(bool(STORE_PATH.fullmatch(path)), "Invalid closure path")
        require(entry.get("path") == path, "Mismatched closure path")
        require(type(entry.get("narSize")) is int and entry["narSize"] >= 0, "Invalid NAR size")
        require(isinstance(entry.get("narHash"), str) and bool(entry["narHash"]), "Missing NAR hash")
        references = entry.get("references")
        require(isinstance(references, list) and all(isinstance(ref, str) for ref in references), "Invalid references")
        require(len(references) == len(set(references)), "Duplicate reference")
        require(set(references) <= metadata.keys(), "Incomplete reference closure")


def closed_public_paths(metadata: dict[str, dict]) -> set[str]:
    public = query_public_paths(sorted(metadata))
    while True:
        closed = {path for path in public if set(metadata[path]["references"]) <= public}
        if closed == public:
            return public
        public = closed


def export_artifact(target: str, tested_sha: str, roots: dict[str, str], source: Path, output: Path) -> None:
    require(target in TARGETS and bool(SHA.fullmatch(tested_sha)), "Invalid artifact identity")
    require(str(source.resolve()) == roots.get("source"), "Source directory must be the immutable source root")
    lock = source / "flake.lock"
    require(lock.is_file(), "Source flake.lock is missing")
    metadata = closure_metadata(roots)
    public = closed_public_paths(metadata)
    require("python" not in roots or roots["python"] in public, "Bootstrap Python must have a fully public reference closure")
    output.mkdir(parents=True, exist_ok=False)
    try:
        with tempfile.TemporaryDirectory(prefix="nix-artifact-", dir=output) as temporary:
            cache = Path(temporary) / "cache"
            (cache / "nar").mkdir(parents=True)
            (cache / "nix-cache-info").write_text("StoreDir: /nix/store\n")
            archive = output / "closure.tar"
            with tarfile.open(archive, "w") as stream:
                stream.add(cache / "nix-cache-info", arcname="cache/nix-cache-info")
                archived_payloads = set()
                for path in sorted(metadata.keys() - public):
                    # Reserve the second copy of this single payload while it
                    # is appended to tar. Earlier payloads live only in tar:
                    # never accumulate a full cache and then duplicate it.
                    allowance = (shutil.disk_usage(cache).free - 64 * 1024 * 1024) // 2
                    require(allowance > 0, "Insufficient disk space for required artifact")
                    exported = export_entry(cache, path, metadata[path], allowance, timeout=600)
                    require(exported is not None, f"Could not export required path: {path}")
                    info, payload, _ = exported
                    stream.add(info, arcname=f"cache/{info.name}")
                    payload_name = f"cache/nar/{payload.name}"
                    if payload_name not in archived_payloads:
                        stream.add(payload, arcname=payload_name)
                        archived_payloads.add(payload_name)
                    info.unlink()
                    payload.unlink()
        manifest = {
            "schemaVersion": 1,
            "target": target,
            "testedSha": tested_sha,
            "roots": dict(sorted(roots.items())),
            "source": {
                "path": roots["source"],
                "narHash": metadata[roots["source"]]["narHash"],
                "flakeLockSha256": sha256(lock),
            },
            "closure": [metadata[path] for path in sorted(metadata)],
            "publicPaths": sorted(public),
            "archiveSha256": sha256(output / "closure.tar"),
        }
        (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
        print(f"Artifact {target}: {len(metadata)} paths, {len(public)} public, {len(roots)} roots")
    except BaseException:
        shutil.rmtree(output)
        raise


def validate_manifest(manifest: dict, target: str, tested_sha: str) -> dict[str, dict]:
    require(manifest.get("schemaVersion") == 1, "Unsupported artifact schema")
    require(target in TARGETS and manifest.get("target") == target, "Artifact target mismatch")
    require(bool(SHA.fullmatch(tested_sha)) and manifest.get("testedSha") == tested_sha, "Artifact SHA mismatch")
    entries = manifest.get("closure")
    require(isinstance(entries, list), "Missing artifact closure")
    metadata = {}
    for entry in entries:
        require(isinstance(entry, dict) and isinstance(entry.get("path"), str), "Invalid closure entry")
        require(entry["path"] not in metadata, "Duplicate closure path")
        metadata[entry["path"]] = entry
    roots = manifest.get("roots")
    require(isinstance(roots, dict), "Missing artifact roots")
    validate_closure(roots, metadata)
    source = manifest.get("source")
    require(isinstance(source, dict) and source.get("path") == roots["source"], "Source root mismatch")
    require(source.get("narHash") == metadata[roots["source"]]["narHash"], "Source NAR mismatch")
    require(isinstance(source.get("flakeLockSha256"), str) and bool(DIGEST.fullmatch(source["flakeLockSha256"])), "Invalid lock digest")
    public = manifest.get("publicPaths")
    require(isinstance(public, list) and all(isinstance(path, str) for path in public), "Invalid public paths")
    require(len(public) == len(set(public)) and set(public) <= metadata.keys(), "Invalid public closure")
    require(all(set(metadata[path]["references"]) <= set(public) for path in public), "Public paths are not a closed reference set")
    require("python" not in roots or roots["python"] in public, "Bootstrap Python must have a fully public reference closure")
    require(isinstance(manifest.get("archiveSha256"), str) and bool(DIGEST.fullmatch(manifest["archiveSha256"])), "Invalid archive digest")
    return metadata


def extract_cache(archive: Path, directory: Path) -> None:
    with tarfile.open(archive) as stream:
        members = stream.getmembers()
        seen = set()
        for member in members:
            path = Path(member.name)
            require(not path.is_absolute() and ".." not in path.parts and path.parts and path.parts[0] == "cache", "Unsafe artifact archive path")
            require(member.name not in seen, "Duplicate artifact archive path")
            seen.add(member.name)
            require(member.isdir() or member.isfile(), "Artifact archive contains a link or special file")
            require(member.size >= 0, "Invalid archive member size")
        # All names and types were checked before any extraction occurs.
        for member in members:
            destination = directory / member.name
            if member.isdir():
                destination.mkdir(parents=True, exist_ok=True)
            else:
                destination.parent.mkdir(parents=True, exist_ok=True)
                source = stream.extractfile(member)
                require(source is not None, "Missing archive member payload")
                with source, destination.open("xb") as output:
                    shutil.copyfileobj(source, output)


def validate_cache(cache: Path, metadata: dict[str, dict], public: set[str]) -> None:
    require((cache / "nix-cache-info").read_text().splitlines() == ["StoreDir: /nix/store"], "Invalid cache store")
    private = metadata.keys() - public
    expected_files = {"nix-cache-info"}
    for path in sorted(private):
        stem = Path(path).name.split("-", 1)[0]
        name = f"{stem}.narinfo"
        info = cache / name
        require(info.is_file(), f"Missing artifact NAR metadata: {path}")
        pairs = [line.split(": ", 1) for line in info.read_text().splitlines() if ": " in line]
        fields = unique_object(pairs)
        entry = metadata[path]
        require(fields.get("StorePath") == path and fields.get("NarHash") == entry["narHash"], "Artifact NAR identity mismatch")
        require(fields.get("NarSize") == str(entry["narSize"]), "Artifact NAR size mismatch")
        refs = fields.get("References", "").split()
        require(set(refs) == {Path(ref).name for ref in entry["references"]}, "Artifact reference mismatch")
        url = fields.get("URL", "")
        require(bool(re.fullmatch(r"nar/[A-Za-z0-9._-]+[.]nar[.]zst", url)), "Unsafe artifact NAR URL")
        payload = cache / url
        require(payload.is_file(), f"Missing artifact NAR payload: {path}")
        require(fields.get("Compression") == "zstd", "Unsupported artifact compression")
        require(fields.get("FileSize") == str(payload.stat().st_size), "Artifact payload size mismatch")
        digest = base64.b64encode(bytes.fromhex(sha256(payload))).decode()
        require(fields.get("FileHash") == f"sha256-{digest}", "Artifact payload digest mismatch")
        expected_files.update((name, url))
    actual = {str(path.relative_to(cache)) for path in cache.rglob("*") if path.is_file()}
    require(actual == expected_files, "Unexpected or missing artifact files")


def import_artifact(target: str, tested_sha: str, directory: Path, source: Path | None = None) -> dict[str, str]:
    manifest = read_json(directory / "manifest.json")
    metadata = validate_manifest(manifest, target, tested_sha)
    archive = directory / "closure.tar"
    require(archive.is_file() and sha256(archive) == manifest["archiveSha256"], "Artifact archive digest mismatch")
    if source is not None:
        require((source / "flake.lock").is_file() and sha256(source / "flake.lock") == manifest["source"]["flakeLockSha256"], "Checkout lock digest mismatch")
    with tempfile.TemporaryDirectory(prefix="nix-artifact-import-") as temporary:
        temporary = Path(temporary)
        extract_cache(archive, temporary)
        cache = temporary / "cache"
        public = set(manifest["publicPaths"])
        validate_cache(cache, metadata, public)
        for start in range(0, len(public), 128):
            subprocess.run(["nix-store", *NO_BUILD, "--realise", *sorted(public)[start : start + 128]], check=True)
        # Public paths already exist in the destination. A recursive copy of
        # roots would still ask the source cache for those omitted paths and
        # references. Copy every private member explicitly without traversing
        # the source closure; dependency completeness was validated above.
        private = sorted(metadata.keys() - public)
        if private:
            subprocess.run(
                ["nix", *NO_BUILD, "copy", "--no-recursive", "--no-check-sigs", "--from", cache.as_uri(), "--stdin"],
                input="".join(f"{path}\n" for path in private),
                text=True,
                check=True,
            )
    imported = Path(manifest["roots"]["source"])
    require((imported / "flake.lock").is_file() and sha256(imported / "flake.lock") == manifest["source"]["flakeLockSha256"], "Imported source lock digest mismatch")
    # Querying existing paths never builds them. Nix verifies payload integrity
    # during import; explicitly compare all resulting NAR identities as well.
    realised = closure_metadata(manifest["roots"])
    require(realised == metadata, "Imported closure identity mismatch")
    roots = manifest["roots"]
    (directory / "roots.json").write_text(json.dumps(roots, indent=2) + "\n")
    (directory / "roots.env").write_text("".join(f"CI_ARTIFACT_ROOT_{name.upper().replace('-', '_')}={shlex.quote(path)}\n" for name, path in sorted(roots.items())))
    return roots


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    export = commands.add_parser("export")
    export.add_argument("--target", choices=TARGETS, required=True)
    export.add_argument("--tested-sha", required=True)
    export.add_argument("--root", action="append", required=True)
    export.add_argument("--source", type=Path, required=True)
    export.add_argument("--output", type=Path, required=True)
    incoming = commands.add_parser("import")
    incoming.add_argument("--target", choices=TARGETS, required=True)
    incoming.add_argument("--tested-sha", required=True)
    incoming.add_argument("--source", type=Path)
    incoming.add_argument("--input", type=Path, required=True)
    arguments = parser.parse_args()
    if arguments.command == "export":
        export_artifact(arguments.target, arguments.tested_sha, roots_from_arguments(arguments.root), arguments.source, arguments.output)
    else:
        import_artifact(arguments.target, arguments.tested_sha, arguments.input, arguments.source)


if __name__ == "__main__":
    main()
