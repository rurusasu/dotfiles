"""Immutable, token-safe Git source staging for Hermes bootstrap."""

from __future__ import annotations

import os
import re
import selectors
import shutil
import stat
import subprocess
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import urlsplit

from .errors import RepositoryError
from .github import GitAuth
from .models import DistributionSource


_GIT_TIMEOUT_SECONDS = 60.0
_MAX_GIT_OUTPUT_BYTES = 4096
_OBJECT_ID = re.compile(r"[0-9a-fA-F]{40,64}\Z")
_GITHUB_OWNER_REPOSITORY_PATH = re.compile(
    r"/[A-Za-z0-9](?:[A-Za-z0-9_.-]*[A-Za-z0-9])?"
    r"/[A-Za-z0-9](?:[A-Za-z0-9_.-]*[A-Za-z0-9])?(?:\.git)?\Z"
)


@dataclass(frozen=True)
class StagedSource:
    declaration: DistributionSource
    path: Path
    commit: str


@dataclass(frozen=True)
class _StageFailure:
    message: str


@dataclass(frozen=True)
class _TreeFailure:
    message: str


def stage_distribution(source: DistributionSource, workdir: Path, auth: GitAuth) -> StagedSource:
    """Clone and verify an exact immutable source snapshot beneath ``workdir``."""

    result = _stage_distribution_boundary(source, workdir, auth)
    if isinstance(result, _StageFailure):
        message = result.message
        del result
        del source
        del workdir
        del auth
        raise RepositoryError(message)
    return result


def _stage_distribution_boundary(
    source: DistributionSource, workdir: Path, auth: GitAuth
) -> StagedSource | _StageFailure:
    """Perform all sensitive subprocess work without leaking its tracebacks."""

    stage: Path | None = None
    askpass: Path | None = None
    try:
        if not _valid_auth(auth) or _remote_identity(source.source) is None or not _valid_ref(source.ref):
            return _StageFailure("could not stage the declared Git source")
        workdir.mkdir(mode=0o700, parents=True, exist_ok=True)
        if not _is_directory(workdir):
            return _StageFailure("could not create a private Git staging directory")
        stage = Path(tempfile.mkdtemp(prefix="stage-", dir=workdir))
        os.chmod(stage, 0o700)
        askpass = _create_askpass(workdir)
        environment = _git_environment(auth, askpass)

        if _run_git(("clone", "--no-checkout", source.source, str(stage)), workdir, environment) is None:
            return _StageFailure("could not stage the declared Git source")
        remote = _run_git(("config", "--get", "remote.origin.url"), stage, environment)
        if remote is None or not _same_remote_identity(source.source, remote):
            return _StageFailure("the staged Git source does not match its declaration")
        if _run_git(("fetch", "--no-tags", "origin", "--", source.ref), stage, environment) is None:
            return _StageFailure("could not fetch the declared Git ref")
        commit = _run_git(("rev-parse", "--verify", "FETCH_HEAD^{commit}"), stage, environment)
        if commit is None or _OBJECT_ID.fullmatch(commit) is None:
            return _StageFailure("the declared Git ref does not resolve to a commit")
        commit = commit.lower()
        if _run_git(("checkout", "--detach", commit), stage, environment) is None:
            return _StageFailure("could not check out the declared Git commit")
        head = _run_git(("rev-parse", "HEAD"), stage, environment)
        if head is None or head.lower() != commit:
            return _StageFailure("the staged Git checkout does not match its resolved commit")
        _remove_git_metadata(stage)
        staged = StagedSource(declaration=source, path=stage, commit=commit)
        _require_manifest(staged)
        assert_safe_distribution_tree(staged)
        stage = None
        return staged
    except Exception:
        return _StageFailure("could not stage the declared Git source")
    finally:
        if askpass is not None:
            _safe_unlink(askpass)
        if stage is not None:
            _safe_remove_tree(stage)


def assert_safe_distribution_tree(stage: StagedSource) -> None:
    """Require a distribution tree made exclusively from regular files and directories."""

    failure = _safe_distribution_tree_boundary(stage)
    if failure is None:
        return
    message = failure.message
    del failure
    del stage
    raise RepositoryError(message)


def _safe_distribution_tree_boundary(stage: StagedSource) -> _TreeFailure | None:
    """Keep staged paths and declarations out of public exception tracebacks."""

    try:
        root = stage.path
        root_stat = root.lstat()
        if not stat.S_ISDIR(root_stat.st_mode) or stat.S_ISLNK(root_stat.st_mode):
            raise RepositoryError("staged Git source contains an unsafe filesystem entry")
        resolved_root = root.resolve(strict=True)
        _walk_safe_tree(root, resolved_root)
    except Exception:
        return _TreeFailure("staged Git source contains an unsafe filesystem entry")
    return None


def _walk_safe_tree(directory: Path, resolved_root: Path) -> None:
    try:
        entries = list(os.scandir(directory))
    except OSError:
        raise RepositoryError("staged Git source contains an unsafe filesystem entry") from None
    for entry in entries:
        path = Path(entry.path)
        try:
            mode = path.lstat().st_mode
            resolved = path.resolve(strict=False)
            resolved.relative_to(resolved_root)
        except (OSError, ValueError):
            raise RepositoryError("staged Git source contains an unsafe filesystem entry") from None
        if stat.S_ISLNK(mode) or not (stat.S_ISDIR(mode) or stat.S_ISREG(mode)):
            raise RepositoryError("staged Git source contains an unsafe filesystem entry")
        if stat.S_ISDIR(mode):
            _walk_safe_tree(path, resolved_root)


def _require_manifest(stage: StagedSource) -> None:
    manifest_name = stage.declaration.manifest_name
    manifest = Path(manifest_name)
    if (
        not manifest_name
        or manifest.is_absolute()
        or manifest.name != manifest_name
        or manifest_name in {".", ".."}
    ):
        raise RepositoryError("the staged Git source is missing its declared manifest")
    candidate = stage.path / manifest
    try:
        mode = candidate.lstat().st_mode
    except OSError:
        raise RepositoryError("the staged Git source is missing its declared manifest") from None
    if stat.S_ISLNK(mode) or not stat.S_ISREG(mode):
        raise RepositoryError("the staged Git source is missing its declared manifest")


def _create_askpass(workdir: Path) -> Path:
    descriptor, name = tempfile.mkstemp(prefix="askpass-", dir=workdir, text=True)
    path = Path(name)
    try:
        os.fchmod(descriptor, 0o700)
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            descriptor = -1
            handle.write("#!/bin/sh\nexec printf '%s\\n' \"$HERMES_BOOTSTRAP_GITHUB_TOKEN\"\n")
            handle.flush()
            os.fsync(handle.fileno())
        return path
    except Exception:
        if descriptor >= 0:
            _safe_close(descriptor)
        _safe_unlink(path)
        raise


def _git_environment(auth: GitAuth, askpass: Path) -> dict[str, str]:
    environment = {
        key: value
        for key, value in os.environ.items()
        if not key.upper().startswith("GIT_")
        and key.upper() not in {"SSH_ASKPASS", "SSH_ASKPASS_REQUIRE"}
    }
    environment.update(
        {
            "GIT_ASKPASS": str(askpass),
            "GIT_TERMINAL_PROMPT": "0",
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": os.devnull,
            "GIT_CONFIG_COUNT": "1",
            "GIT_CONFIG_KEY_0": "credential.helper",
            "GIT_CONFIG_VALUE_0": "",
            "HERMES_BOOTSTRAP_GITHUB_TOKEN": auth.token,
        }
    )
    return environment


def _run_git(arguments: tuple[str, ...], cwd: Path, environment: dict[str, str]) -> str | None:
    """Run Git without a shell and retain only a small, non-secret result."""

    process: subprocess.Popen[bytes] | None = None
    output_stream: object | None = None
    selector: selectors.BaseSelector | None = None
    output = bytearray()
    try:
        process = subprocess.Popen(
            ("git", *arguments),
            cwd=cwd,
            env=environment,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            close_fds=True,
        )
        output_stream = process.stdout
        if output_stream is None:
            return None
        descriptor = output_stream.fileno()
        os.set_blocking(descriptor, False)
        selector = selectors.DefaultSelector()
        selector.register(output_stream, selectors.EVENT_READ)
        deadline = time.monotonic() + _GIT_TIMEOUT_SECONDS
        end_of_output = False

        while not end_of_output:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                _stop_git_process(process)
                return None
            for _key, _events in selector.select(remaining):
                chunk = os.read(descriptor, _MAX_GIT_OUTPUT_BYTES + 1 - len(output))
                if not chunk:
                    selector.unregister(output_stream)
                    end_of_output = True
                    break
                output.extend(chunk)
                if len(output) > _MAX_GIT_OUTPUT_BYTES:
                    _stop_git_process(process)
                    return None

        remaining = deadline - time.monotonic()
        if remaining <= 0 or process.wait(timeout=remaining) != 0:
            return None
        return bytes(output).decode("ascii", "strict").strip()
    except (BlockingIOError, OSError, subprocess.SubprocessError, UnicodeError, ValueError):
        return None
    finally:
        if selector is not None:
            selector.close()
        if output_stream is not None:
            try:
                output_stream.close()
            except OSError:
                pass
        if process is not None and process.poll() is None:
            _stop_git_process(process)


def _stop_git_process(process: subprocess.Popen[bytes]) -> None:
    """Kill and reap a failed Git child before dropping its bounded output."""

    if process.poll() is None:
        try:
            process.kill()
        except OSError:
            pass
    try:
        process.wait()
    except (OSError, subprocess.SubprocessError):
        pass


def _remove_git_metadata(stage: Path) -> None:
    metadata = stage / ".git"
    try:
        mode = metadata.lstat().st_mode
    except OSError:
        raise RepositoryError("could not remove staged Git metadata") from None
    if stat.S_ISLNK(mode):
        raise RepositoryError("could not remove staged Git metadata")
    if stat.S_ISDIR(mode):
        shutil.rmtree(metadata)
    elif stat.S_ISREG(mode):
        metadata.unlink()
    else:
        raise RepositoryError("could not remove staged Git metadata")


def _same_remote_identity(declared: str, observed: str) -> bool:
    return _remote_identity(declared) == _remote_identity(observed)


def _remote_identity(value: str) -> tuple[str, str, str] | None:
    parsed = urlsplit(value)
    if parsed.scheme:
        if (
            parsed.scheme.casefold() != "https"
            or parsed.netloc.casefold() != "github.com"
            or parsed.username is not None
            or parsed.password is not None
            or parsed.query
            or parsed.fragment
            or _GITHUB_OWNER_REPOSITORY_PATH.fullmatch(parsed.path) is None
        ):
            return None
        path = parsed.path
        if path.endswith(".git"):
            path = path[:-4]
        return ("https", "github.com", path.casefold())
    if not Path(value).is_absolute():
        return None
    try:
        return ("file", "", str(Path(value).resolve(strict=False)))
    except (OSError, ValueError):
        return None


def _is_directory(path: Path) -> bool:
    try:
        mode = path.lstat().st_mode
    except OSError:
        return False
    return stat.S_ISDIR(mode) and not stat.S_ISLNK(mode)


def _valid_auth(auth: object) -> bool:
    return (
        isinstance(auth, GitAuth)
        and isinstance(auth.token, str)
        and bool(auth.token)
        and auth.token == auth.token.strip()
    )


def _valid_ref(value: object) -> bool:
    if not isinstance(value, str) or not value or value != value.strip():
        return False
    components = value.split("/")
    return not (
        value == "@"
        or value.startswith(("-", "/"))
        or value.endswith((".", "/"))
        or ".." in value
        or "@{" in value
        or "//" in value
        or any(component.startswith(".") or component.endswith(".lock") for component in components)
        or any(character in value for character in " ~^:?*[\\")
        or any(ord(character) < 32 or ord(character) == 127 for character in value)
    )


def _safe_remove_tree(path: Path) -> None:
    try:
        if path.is_dir() and not path.is_symlink():
            shutil.rmtree(path)
        else:
            path.unlink(missing_ok=True)
    except OSError:
        pass


def _safe_unlink(path: Path) -> None:
    try:
        path.unlink(missing_ok=True)
    except OSError:
        pass


def _safe_close(descriptor: int) -> None:
    try:
        os.close(descriptor)
    except OSError:
        pass
