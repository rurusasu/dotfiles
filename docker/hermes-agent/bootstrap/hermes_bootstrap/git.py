"""Immutable, token-safe Git source staging for Hermes bootstrap."""

from __future__ import annotations

import os
import re
import shutil
import stat
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import urlsplit

from .errors import RepositoryError
from .github import GitAuth
from .models import DistributionSource


_GIT_TIMEOUT_SECONDS = 60.0
_MAX_GIT_OUTPUT_BYTES = 4096
_OBJECT_ID = re.compile(r"[0-9a-fA-F]{40,64}\Z")


@dataclass(frozen=True)
class StagedSource:
    declaration: DistributionSource
    path: Path
    commit: str


@dataclass(frozen=True)
class _StageFailure:
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
        if not _valid_auth(auth) or _remote_identity(source.source) is None:
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
        if _run_git(("fetch", "--no-tags", "origin", source.ref), stage, environment) is None:
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

    root = stage.path
    try:
        root_stat = root.lstat()
        if not stat.S_ISDIR(root_stat.st_mode) or stat.S_ISLNK(root_stat.st_mode):
            raise RepositoryError("staged Git source contains an unsafe filesystem entry")
        resolved_root = root.resolve(strict=True)
        _walk_safe_tree(root, resolved_root)
    except RepositoryError:
        raise
    except (OSError, ValueError):
        raise RepositoryError("staged Git source contains an unsafe filesystem entry") from None


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
    environment = os.environ.copy()
    environment.update(
        {
            "GIT_ASKPASS": str(askpass),
            "GIT_TERMINAL_PROMPT": "0",
            "HERMES_BOOTSTRAP_GITHUB_TOKEN": auth.token,
        }
    )
    return environment


def _run_git(arguments: tuple[str, ...], cwd: Path, environment: dict[str, str]) -> str | None:
    """Run Git without a shell and retain only a small, non-secret result."""

    try:
        with tempfile.TemporaryFile() as output_file:
            result = subprocess.run(
                ("git", *arguments),
                cwd=cwd,
                env=environment,
                stdin=subprocess.DEVNULL,
                stdout=output_file,
                stderr=subprocess.DEVNULL,
                check=False,
                timeout=_GIT_TIMEOUT_SECONDS,
            )
            if result.returncode != 0 or output_file.tell() > _MAX_GIT_OUTPUT_BYTES:
                return None
            output_file.seek(0)
            output = output_file.read(_MAX_GIT_OUTPUT_BYTES)
        if not isinstance(output, bytes):
            return None
        return output.decode("ascii", "strict").strip()
    except (OSError, subprocess.SubprocessError, UnicodeError):
        return None


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
        if parsed.username is not None or parsed.password is not None or parsed.query or parsed.fragment:
            return None
        path = parsed.path.rstrip("/")
        if path.endswith(".git"):
            path = path[:-4]
        return (parsed.scheme.casefold(), parsed.netloc.casefold(), path.casefold())
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
