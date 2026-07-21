"""Command-line interface for the Hermes bootstrap runtime."""

from __future__ import annotations

import argparse
import json
import os
import sys
import traceback
from collections.abc import Mapping, Sequence
from typing import TextIO

from . import app
from .errors import BootstrapError, InputError


DEFAULT_MANIFEST = "/usr/local/share/hermes-bootstrap/bootstrap-manifest.yaml"


def main(
    argv: Sequence[str] | None = None,
    *,
    stdin: TextIO | None = None,
    stdout: TextIO | None = None,
    stderr: TextIO | None = None,
    environ: Mapping[str, str] | None = None,
) -> int:
    """Run one command, returning an explicit process status for tests and entrypoints."""

    stdin = sys.stdin if stdin is None else stdin
    stdout = sys.stdout if stdout is None else stdout
    stderr = sys.stderr if stderr is None else stderr
    environ = os.environ if environ is None else environ
    parser = _parser()
    try:
        args = parser.parse_args(argv)
    except BootstrapError as error:
        _write_error(stderr, str(error))
        return error.exit_code
    try:
        if args.command == "secret-plan":
            result = app.secret_plan(args.manifest)
        elif args.command == "apply":
            result = app.apply(args.manifest, stdin)
        elif args.command == "validate":
            result = app.validate(args.manifest)
        else:
            result = app.sync_repository(args.manifest, args.name, environ)
        _write_json(stdout, result)
        return 0
    except BrokenPipeError:
        return 0
    except BootstrapError as error:
        _write_error(stderr, str(error))
        _write_debug(stderr, error, environ)
        return error.exit_code
    except Exception as error:
        _write_error(stderr, "bootstrap command failed")
        _write_debug(stderr, error, environ)
        return 6


class _Parser(argparse.ArgumentParser):
    def error(self, _message: str) -> None:
        raise InputError("invalid command arguments")


def _parser() -> argparse.ArgumentParser:
    parser = _Parser(prog="hermes-bootstrap")
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("secret-plan", "apply", "validate"):
        command = commands.add_parser(name)
        command.add_argument("--manifest", default=DEFAULT_MANIFEST, type=_path)
    sync = commands.add_parser("sync-repository")
    sync.add_argument("name")
    sync.add_argument("--manifest", default=DEFAULT_MANIFEST, type=_path)
    return parser


def _path(value: str):
    from pathlib import Path

    return Path(value)


def _write_json(stream: TextIO, value: object) -> None:
    stream.write(json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n")
    stream.flush()


def _write_error(stream: TextIO, message: str) -> None:
    try:
        stream.write(message + "\n")
        stream.flush()
    except BrokenPipeError:
        pass


def _write_debug(stream: TextIO, error: BaseException, environ: Mapping[str, str]) -> None:
    if environ.get("HERMES_BOOTSTRAP_DEBUG") != "1":
        return
    try:
        stream.write("".join(traceback.format_exception(type(error), error, error.__traceback__)))
        stream.flush()
    except BrokenPipeError:
        pass
