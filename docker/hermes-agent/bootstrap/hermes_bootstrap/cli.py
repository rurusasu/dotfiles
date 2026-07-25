"""Command-line interface for the Hermes bootstrap runtime."""

from __future__ import annotations

import argparse
import json
import os
import sys
import traceback
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from typing import TextIO

from . import app
from .errors import ApplyError, BootstrapError, InputError


DEFAULT_MANIFEST = "/usr/local/share/hermes-bootstrap/bootstrap-manifest.yaml"


@dataclass(frozen=True)
class _CommandOutcome:
    result: object | None = None
    exit_code: int = 0
    error_type: type[BootstrapError] | None = None
    message: str | None = None


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
    debug = environ.get("HERMES_BOOTSTRAP_DEBUG") == "1"
    outcome = _dispatch_boundary(args, stdin, environ)
    del stdin, environ
    try:
        if outcome.error_type is not None:
            error_type = outcome.error_type
            message = outcome.message or "bootstrap command failed"
            del outcome
            raise error_type(message) from None
        exit_code = outcome.exit_code
        result = outcome.result
        del outcome
        _write_json(stdout, result)
        return exit_code
    except BrokenPipeError:
        return 0
    except BootstrapError as error:
        _write_error(stderr, str(error))
        _write_debug(stderr, error, debug)
        return error.exit_code
    except Exception as error:
        _write_error(stderr, "bootstrap command failed")
        _write_debug(stderr, error, debug)
        return 6


def _dispatch_boundary(
    args: argparse.Namespace, stdin: TextIO, environ: Mapping[str, str]
) -> _CommandOutcome:
    try:
        if args.command == "secret-plan":
            result = app.secret_plan(args.manifest)
        elif args.command == "apply":
            result = app.apply(args.manifest, stdin)
        elif args.command == "validate":
            result = app.validate(args.manifest)
        elif args.command == "sync-repository":
            result = app.sync_repository(args.manifest, args.name, environ)
        elif args.command == "sync-profiles":
            report = app.sync_profiles(
                args.manifest,
                dry_run=args.dry_run,
                environ=environ,
            )
            result = report.as_dict()
            return _CommandOutcome(result=result, exit_code=report.exit_code)
        else:
            return _CommandOutcome(
                error_type=InputError,
                message="invalid command arguments",
            )
        return _CommandOutcome(result=result, exit_code=0)
    except BootstrapError as error:
        outcome = _CommandOutcome(error_type=type(error), message=str(error))
        del error
        return outcome
    except Exception:
        return _CommandOutcome(error_type=ApplyError, message="bootstrap command failed")


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
    sync_profiles = commands.add_parser("sync-profiles")
    sync_profiles.add_argument("--dry-run", action="store_true")
    sync_profiles.add_argument("--manifest", default=DEFAULT_MANIFEST, type=_path)
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


def _write_debug(stream: TextIO, error: BaseException, enabled: bool) -> None:
    if not enabled:
        return
    try:
        stream.write("".join(traceback.format_exception(type(error), error, error.__traceback__)))
        stream.flush()
    except BrokenPipeError:
        pass
