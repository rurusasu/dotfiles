"""Provision a missing memory provider from the Hermes image's own catalog.

Providers that leave core must still be available to every isolated profile.
The upstream catalog owns the reviewed source; dotfiles does not duplicate its
version or commit. Installation is explicit at image build time because the
runtime disables lazy installs and acceptance homes contain no plugin code.
"""

from __future__ import annotations

import io
import re
import shutil
import subprocess
import tarfile
import tempfile
from importlib.metadata import PackageNotFoundError, version
from pathlib import Path, PurePosixPath

import yaml
from packaging.requirements import Requirement


def verify_provider_dependencies(hermes_root: Path, name: str) -> None:
    """Reject missing dependencies before importing providers can trigger upgrades."""
    manifest = hermes_root / "plugins" / "memory" / name / "plugin.yaml"
    metadata = yaml.safe_load(manifest.read_text(encoding="utf-8"))
    if not isinstance(metadata, dict) or not isinstance(
        metadata.get("pip_dependencies"), list
    ):
        raise TypeError(f"Missing provider dependency metadata: {manifest}")
    for specification in metadata["pip_dependencies"]:
        requirement = Requirement(specification)
        if requirement.marker is not None and not requirement.marker.evaluate():
            continue
        try:
            installed = version(requirement.name)
        except PackageNotFoundError as exc:
            raise RuntimeError(
                f"Provider dependency is missing: {requirement.name}"
            ) from exc
        if installed not in requirement.specifier:
            raise RuntimeError(
                f"Provider dependency mismatch: {requirement} (installed {installed})"
            )


def install_provider(hermes_root: Path, name: str) -> None:
    """Keep a bundled provider or install the source reviewed with this Hermes image."""
    if not re.fullmatch(r"[a-z0-9_-]+", name):
        raise ValueError("Invalid memory provider name")
    destination = hermes_root / "plugins" / "memory" / name
    if (destination / "__init__.py").is_file():
        return
    if destination.exists() or destination.is_symlink():
        raise RuntimeError(f"Incomplete provider directory: {destination}")
    catalog_path = hermes_root / "plugin-catalog" / f"{name}.yaml"
    try:
        entry = yaml.safe_load(catalog_path.read_text(encoding="utf-8"))
    except (OSError, yaml.YAMLError) as exc:
        raise RuntimeError(
            f"Missing or unreadable provider catalog: {catalog_path}"
        ) from exc
    if not isinstance(entry, dict) or entry.get("name") != name:
        raise ValueError(f"Invalid provider catalog entry: {catalog_path}")
    repo, sha, subdir = (entry.get(key) for key in ("repo", "sha", "subdir"))
    if not isinstance(repo, str) or not repo:
        raise ValueError("Provider catalog repo is missing")
    if not isinstance(sha, str) or not re.fullmatch(r"[0-9a-f]{40}", sha):
        raise ValueError("Provider catalog SHA is invalid")
    if not isinstance(subdir, str) or not subdir:
        raise ValueError("Provider catalog subdir is missing")
    relative = PurePosixPath(subdir)
    if relative.is_absolute() or ".." in relative.parts:
        raise ValueError("Provider catalog subdir must stay within its repository")

    with tempfile.TemporaryDirectory(prefix="hermes-memory-provider-") as directory:
        checkout = Path(directory) / "checkout"
        checkout.mkdir()

        def git(*args: str) -> bytes:
            return subprocess.check_output(["git", "-C", str(checkout), *args])

        git("init", "--quiet")
        git("remote", "add", "origin", repo)
        git("fetch", "--quiet", "--depth", "1", "--filter=blob:none", "origin", sha)
        if git("rev-parse", "FETCH_HEAD").decode().strip() != sha:
            raise RuntimeError(
                "Fetched provider does not match the upstream catalog SHA"
            )
        archive = git("archive", "--prefix=provider/", f"FETCH_HEAD:{subdir}")
        extracted = Path(directory) / "extracted"
        extracted.mkdir()
        with tarfile.open(fileobj=io.BytesIO(archive)) as contents:
            contents.extractall(extracted, filter="data")
        source = extracted / "provider"
        if (
            not (source / "__init__.py").is_file()
            or not (source / "plugin.yaml").is_file()
        ):
            raise RuntimeError("Catalog source is not an installable memory provider")
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(source), str(destination))


if __name__ == "__main__":
    install_provider(Path("/opt/hermes"), "hindsight")
    verify_provider_dependencies(Path("/opt/hermes"), "hindsight")
