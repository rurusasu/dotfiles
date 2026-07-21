#!/usr/bin/env sh
set -eu

if [ -n "${GH_TOKEN:-}" ]; then
  unset GITHUB_PERSONAL_ACCESS_TOKEN GITHUB_TOKEN
  exec /usr/bin/gh "$@"
fi

if token=$(
  /opt/hermes/.venv/bin/python - "${HERMES_HOME:-}" <<'PY'
import os
import stat
import sys
from pathlib import Path


LIMIT = 1024 * 1024
KEYS = ("GH_TOKEN", "GITHUB_PERSONAL_ACCESS_TOKEN", "GITHUB_TOKEN")


class InvalidEnvironment(Exception):
    pass


def safe_directory(path):
    if not path.is_absolute():
        return False
    current = path
    while True:
        try:
            metadata = current.lstat()
        except OSError:
            return False
        if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
            return False
        if current.parent == current:
            return True
        current = current.parent


def safe_home(root, candidate):
    if not candidate.is_absolute():
        return False
    normalized = Path(os.path.normpath(candidate))
    if candidate != normalized:
        return False
    try:
        relative = normalized.relative_to(root)
    except ValueError:
        return False
    if not safe_directory(root):
        return False
    current = root
    for component in relative.parts:
        current /= component
        try:
            metadata = current.lstat()
        except OSError:
            return False
        if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
            return False
    return True


def unbalanced_quotes(value):
    return value.count("'") % 2 or value.count('"') % 2


def is_malformed_supported_line(line):
    for key in KEYS:
        if line == key or (line.startswith(key) and line[len(key) : len(key) + 1] in (" ", "\t")):
            return True
        prefix = "export " + key
        if line == prefix or line.startswith(prefix + "=") or line.startswith(prefix + " ") or line.startswith(prefix + "\t"):
            return True
    return False


def read_environment(path):
    try:
        metadata = path.lstat()
    except FileNotFoundError:
        return None
    except OSError as error:
        raise InvalidEnvironment from error
    if (
        stat.S_ISLNK(metadata.st_mode)
        or not stat.S_ISREG(metadata.st_mode)
        or metadata.st_nlink != 1
        or metadata.st_size > LIMIT
    ):
        raise InvalidEnvironment

    descriptor = None
    try:
        descriptor = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
        opened = os.fstat(descriptor)
        if (
            not stat.S_ISREG(opened.st_mode)
            or opened.st_nlink != 1
            or opened.st_dev != metadata.st_dev
            or opened.st_ino != metadata.st_ino
            or opened.st_size > LIMIT
        ):
            raise InvalidEnvironment
        chunks = []
        size = 0
        while True:
            chunk = os.read(descriptor, 65536)
            if not chunk:
                break
            size += len(chunk)
            if size > LIMIT:
                raise InvalidEnvironment
            chunks.append(chunk)
    except (OSError, InvalidEnvironment) as error:
        raise InvalidEnvironment from error
    finally:
        if descriptor is not None:
            try:
                os.close(descriptor)
            except OSError as error:
                raise InvalidEnvironment from error

    try:
        text = b"".join(chunks).decode("utf-8")
    except UnicodeDecodeError as error:
        raise InvalidEnvironment from error
    if "\x00" in text:
        raise InvalidEnvironment

    values = {}
    for line in text.split("\n"):
        key = next((item for item in KEYS if line.startswith(item + "=")), None)
        if key is None:
            if is_malformed_supported_line(line):
                raise InvalidEnvironment
            continue
        if key in values:
            raise InvalidEnvironment
        value = line[len(key) + 1 :]
        if "\r" in value or "\n" in value or unbalanced_quotes(value):
            raise InvalidEnvironment
        values[key] = value
    return next((values[key] for key in KEYS if values.get(key)), None)


def main():
    root = Path("/opt/data")
    active = sys.argv[1]
    paths = [root / ".env"]
    if active:
        home = Path(active)
        if not safe_home(root, home):
            raise InvalidEnvironment
        active_path = home / ".env"
        paths = [active_path] if active_path == paths[0] else [active_path, paths[0]]
    for path in paths:
        token = read_environment(path)
        if token is not None:
            sys.stdout.write(token)
            return 0
    return 3


try:
    raise SystemExit(main())
except InvalidEnvironment:
    raise SystemExit(1)
PY
); then
  unset GITHUB_PERSONAL_ACCESS_TOKEN GITHUB_TOKEN
  export GH_TOKEN="$token"
  exec /usr/bin/gh "$@"
else
  status=$?
fi

if [ "$status" -eq 3 ]; then
  printf '%s\n' 'GitHub credentials are missing; rerun the Hermes installer.' >&2
else
  printf '%s\n' 'GitHub credentials are invalid; rerun the Hermes installer.' >&2
fi
exit 1
