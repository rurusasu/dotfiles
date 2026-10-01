"""Bind the real test CLI to private state for one native test build."""

from __future__ import annotations

import argparse
import os
import shlex
import subprocess
import tempfile
from collections.abc import Iterator
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path

import yaml


HOME_MARKER = "/__hermes_bootstrap_test_home__"


@dataclass(frozen=True)
class BuildFixture:
    root: Path
    home: Path
    manifest: Path
    executable: Path


@contextmanager
def private_fixture(
    template: Path,
    bootstrap_cli: Path,
    temporary_root: Path,
    shell: str,
) -> Iterator[BuildFixture]:
    # Darwin's TMPDIR may name a symlinked ancestor. Bind only canonical paths,
    # without weakening the production no-follow traversal of managed state.
    canonical_root = temporary_root.resolve(strict=True)
    with tempfile.TemporaryDirectory(prefix="hermes-build-", dir=canonical_root) as temporary:
        root = Path(temporary)
        home = root / "home"
        home.mkdir(mode=0o700)
        manifest = root / "manifest.yaml"
        source = template.read_text(encoding="utf-8")
        if HOME_MARKER not in source:
            raise ValueError("manifest template has no home marker")

        def bind_scalar(value: object) -> object:
            if isinstance(value, str):
                return value.replace(HOME_MARKER, str(home))
            if isinstance(value, list):
                return [bind_scalar(item) for item in value]
            if isinstance(value, dict):
                return {key: bind_scalar(item) for key, item in value.items()}
            return value

        # The trusted Nix-generated template remains the schema SSOT. Render
        # bound scalars with YAML quoting, not text injection into plain values.
        bound = bind_scalar(yaml.safe_load(source))
        manifest.write_text(yaml.safe_dump(bound, sort_keys=False), encoding="utf-8")
        executable = root / "hermes-bootstrap"
        executable.write_text(
            f"#!{shell}\n"
            f"export HERMES_HOME={shlex.quote(str(home))}\n"
            f"export HERMES_BOOTSTRAP_MANIFEST={shlex.quote(str(manifest))}\n"
            f"exec {shlex.quote(str(bootstrap_cli))} \"$@\"\n",
            encoding="utf-8",
        )
        executable.chmod(0o700)
        yield BuildFixture(root, home, manifest, executable)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest-template", type=Path, required=True)
    parser.add_argument("--bootstrap-cli", type=Path, required=True)
    parser.add_argument("--temporary-root", type=Path, required=True)
    parser.add_argument("--shell", required=True)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command:
        parser.error("a test command is required")
    with private_fixture(
        args.manifest_template, args.bootstrap_cli, args.temporary_root, args.shell
    ) as fixture:
        environment = os.environ.copy()
        environment["DOTFILES_HERMES_BOOTSTRAP_EXECUTABLE"] = str(fixture.executable)
        environment["DOTFILES_HERMES_TEST_BASE_CLI"] = str(args.bootstrap_cli)
        environment["DOTFILES_HERMES_TEST_MANIFEST_TEMPLATE"] = str(args.manifest_template)
        environment["DOTFILES_HERMES_TEST_SHELL"] = args.shell
        environment["PATH"] = f"{fixture.root}:{environment.get('PATH', '')}"
        return subprocess.run(command, env=environment, check=False).returncode


if __name__ == "__main__":
    raise SystemExit(main())
