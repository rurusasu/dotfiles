#!/usr/bin/env python3
"""Route changed repository paths to CI platform and processing outputs."""

from __future__ import annotations

import argparse
import json
import sys
from collections.abc import Iterable
from pathlib import Path, PurePosixPath
from typing import Any


EXPECTED_OUTPUTS = frozenset(
    {
        "linux",
        "darwin",
        "wsl",
        "windows",
        "contract",
        "nix",
        "chezmoi",
        "hermes",
        "devcontainer",
        "package_catalog",
    }
)
DEFAULT_MANIFEST_PATH = Path(__file__).resolve().parents[2] / "ci" / "path-routing.json"


def route_paths(paths: Iterable[str], manifest_path: Path) -> dict[str, bool]:
    """Return the union of manifest outputs selected by repository-relative paths."""
    outputs, rules = _load_manifest(manifest_path)
    selected = {output: output == "contract" for output in outputs}

    for raw_path in paths:
        path = _validate_path(raw_path)
        for rule in rules:
            if any(path.full_match(pattern) for pattern in rule["patterns"]):
                for output in rule["outputs"]:
                    selected[output] = True

    return selected


def _load_manifest(manifest_path: Path) -> tuple[list[str], list[dict[str, list[str]]]]:
    manifest: Any = json.loads(manifest_path.read_text(encoding="utf-8"))
    if not isinstance(manifest, dict) or manifest.get("version") != 1:
        raise ValueError("routing manifest must use version 1")

    outputs = manifest.get("outputs")
    if not isinstance(outputs, list) or set(outputs) != EXPECTED_OUTPUTS or len(outputs) != len(EXPECTED_OUTPUTS):
        raise ValueError("routing manifest outputs must be the supported output names")
    if not all(isinstance(output, str) for output in outputs):
        raise ValueError("routing manifest outputs must be strings")

    rules = manifest.get("rules")
    if not isinstance(rules, list):
        raise ValueError("routing manifest rules must be a list")

    validated_rules: list[dict[str, list[str]]] = []
    for rule in rules:
        if not isinstance(rule, dict):
            raise ValueError("routing manifest rule must be an object")
        patterns = rule.get("patterns")
        rule_outputs = rule.get("outputs")
        if (
            not isinstance(patterns, list)
            or not patterns
            or not all(isinstance(pattern, str) for pattern in patterns)
            or not isinstance(rule_outputs, list)
            or not rule_outputs
            or not all(isinstance(output, str) for output in rule_outputs)
            or not set(rule_outputs).issubset(EXPECTED_OUTPUTS)
        ):
            raise ValueError("routing manifest rule contains invalid patterns or outputs")
        validated_rules.append({"patterns": patterns, "outputs": rule_outputs})

    return outputs, validated_rules


def _validate_path(raw_path: str) -> PurePosixPath:
    if "\\" in raw_path:
        raise ValueError(f"path must use forward slashes: {raw_path}")

    path = PurePosixPath(raw_path)
    if path.is_absolute() or ".." in path.parts:
        raise ValueError(f"path must be repository-relative: {raw_path}")
    return path


def _read_paths(paths_file: Path) -> list[str]:
    if paths_file == Path("-"):
        return sys.stdin.read().splitlines()
    return paths_file.read_text(encoding="utf-8").splitlines()


def _write_github_output(path: Path, result: dict[str, bool]) -> None:
    path.write_text(
        "".join(f"{name}={str(result[name]).lower()}\n" for name in sorted(result)),
        encoding="utf-8",
    )


def _parse_arguments(arguments: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST_PATH)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--paths-file", type=Path)
    source.add_argument("--all", action="store_true")
    parser.add_argument("--github-output", type=Path)
    return parser.parse_args(arguments)


def main(arguments: list[str] | None = None) -> int:
    args = _parse_arguments(arguments)
    if args.all:
        outputs, _ = _load_manifest(args.manifest)
        result = dict.fromkeys(outputs, True)
    else:
        result = route_paths(_read_paths(args.paths_file), args.manifest)

    if args.github_output is not None:
        _write_github_output(args.github_output, result)
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
