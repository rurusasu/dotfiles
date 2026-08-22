#!/usr/bin/env python3
"""Route changed repository paths to CI platform and processing outputs."""

from __future__ import annotations

import argparse
import json
import sys
from collections.abc import Iterable
from fnmatch import fnmatchcase
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
PLATFORM_OUTPUTS = frozenset({"linux", "darwin", "wsl", "windows"})
DEFAULT_MANIFEST_PATH = Path(__file__).resolve().parents[2] / "ci" / "path-routing.json"


def route_paths(paths: Iterable[str], manifest_path: Path) -> dict[str, bool]:
    """Return the union of manifest outputs selected by repository-relative paths."""
    outputs, rules, fallback_outputs = _load_manifest(manifest_path)
    selected = {output: output == "contract" for output in outputs}

    for raw_path in paths:
        path = _validate_path(raw_path)
        matched_platform = False
        for rule in rules:
            if any(_full_match(path, pattern) for pattern in rule["patterns"]):
                matched_platform |= bool(PLATFORM_OUTPUTS.intersection(rule["outputs"]))
                for output in rule["outputs"]:
                    selected[output] = True
        if not matched_platform:
            for output in fallback_outputs:
                selected[output] = True

    return selected


def _full_match(path: PurePosixPath, pattern: str) -> bool:
    """Match an anchored POSIX glob with recursive ``**`` on Python 3.12+."""
    path_parts = path.parts
    pattern_parts = PurePosixPath(pattern).parts

    def match(path_index: int, pattern_index: int) -> bool:
        if pattern_index == len(pattern_parts):
            return path_index == len(path_parts)

        pattern_part = pattern_parts[pattern_index]
        if pattern_part == "**":
            return match(path_index, pattern_index + 1) or (
                path_index < len(path_parts) and match(path_index + 1, pattern_index)
            )

        return (
            path_index < len(path_parts)
            and fnmatchcase(path_parts[path_index], pattern_part)
            and match(path_index + 1, pattern_index + 1)
        )

    return match(0, 0)


def _load_manifest(
    manifest_path: Path,
) -> tuple[list[str], list[dict[str, list[str]]], list[str]]:
    manifest: Any = json.loads(manifest_path.read_text(encoding="utf-8"))
    required_keys = {"version", "outputs", "rules"}
    allowed_keys = required_keys | {"fallback_outputs"}
    if (
        not isinstance(manifest, dict)
        or not required_keys.issubset(manifest)
        or not set(manifest).issubset(allowed_keys)
    ):
        raise ValueError("routing manifest root keys are invalid")

    version = manifest["version"]
    if type(version) is not int or version != 1:
        raise ValueError("routing manifest must use version 1")

    outputs = manifest.get("outputs")
    if (
        not isinstance(outputs, list)
        or len(outputs) != len(EXPECTED_OUTPUTS)
        or not all(isinstance(output, str) for output in outputs)
        or set(outputs) != EXPECTED_OUTPUTS
    ):
        raise ValueError("routing manifest outputs must be strings")

    fallback_outputs = manifest.get("fallback_outputs", [])
    if (
        not isinstance(fallback_outputs, list)
        or not all(isinstance(output, str) for output in fallback_outputs)
        or not set(fallback_outputs).issubset(EXPECTED_OUTPUTS)
    ):
        raise ValueError("routing manifest fallback outputs must be known strings")

    rules = manifest.get("rules")
    if not isinstance(rules, list):
        raise ValueError("routing manifest rules must be a list")

    validated_rules: list[dict[str, list[str]]] = []
    for rule in rules:
        if not isinstance(rule, dict) or set(rule) != {"patterns", "outputs"}:
            raise ValueError("routing manifest rule keys are invalid")
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
        validated_rules.append(
            {
                "patterns": [_validate_pattern(pattern) for pattern in patterns],
                "outputs": rule_outputs,
            }
        )

    return outputs, validated_rules, fallback_outputs


def _validate_path(raw_path: str) -> PurePosixPath:
    if "\\" in raw_path:
        raise ValueError(f"path must use forward slashes: {raw_path}")

    path = PurePosixPath(raw_path)
    if path.is_absolute() or ".." in path.parts:
        raise ValueError(f"path must be repository-relative: {raw_path}")
    return path


def _validate_pattern(pattern: str) -> str:
    if not pattern or "\\" in pattern:
        raise ValueError(f"routing pattern must be a nonempty POSIX-relative path: {pattern}")

    path = PurePosixPath(pattern)
    if path.is_absolute() or ".." in path.parts:
        raise ValueError(f"routing pattern must be a nonempty POSIX-relative path: {pattern}")
    return pattern


def _read_paths(paths_file: Path) -> list[str]:
    if paths_file == Path("-"):
        return sys.stdin.read().splitlines()
    return paths_file.read_text(encoding="utf-8").splitlines()


def _write_github_output(path: Path, result: dict[str, bool]) -> None:
    path.write_text(
        "".join(f"{name}={str(result[name]).lower()}\n" for name in sorted(result)),
        encoding="utf-8",
    )


def _argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST_PATH)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--paths-file", type=Path)
    source.add_argument("--all", action="store_true")
    parser.add_argument("--github-output", type=Path)
    return parser


def _parse_arguments(arguments: list[str] | None = None) -> argparse.Namespace:
    return _argument_parser().parse_args(arguments)


def main(arguments: list[str] | None = None) -> int:
    parser = _argument_parser()
    args = parser.parse_args(arguments)
    try:
        if args.all:
            outputs, _, _ = _load_manifest(args.manifest)
            result = dict.fromkeys(outputs, True)
        else:
            result = route_paths(_read_paths(args.paths_file), args.manifest)
    except ValueError as error:
        parser.error(str(error))

    if args.github_output is not None:
        _write_github_output(args.github_output, result)
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
