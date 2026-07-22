#!/usr/bin/env sh
set -eu

if [ -n "${GH_TOKEN:-}" ]; then
  unset GITHUB_PERSONAL_ACCESS_TOKEN GITHUB_TOKEN
  exec /usr/bin/gh "$@"
fi

exec /opt/hermes/.venv/bin/python - "$@" 3<&0 <<'PY'
import os
import signal
import stat
import sys
from io import StringIO

from dotenv.parser import parse_stream


LIMIT = 1024 * 1024
KEYS = ("GH_TOKEN", "GITHUB_PERSONAL_ACCESS_TOKEN", "GITHUB_TOKEN")
ROOT = "/opt/data"
DIRECTORY_FLAGS = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
FILE_FLAGS = os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW | os.O_CLOEXEC
SAVED_STDIN = 3
MISSING_MESSAGE = "GitHub credentials are missing; rerun the Hermes installer."
INVALID_MESSAGE = "GitHub credentials are invalid; rerun the Hermes installer."


class InvalidEnvironment(Exception):
    pass


def home_components(candidate):
    if not candidate:
        return ()
    if candidate == ROOT:
        return ()
    prefix = ROOT + "/"
    if not candidate.startswith(prefix) or os.path.normpath(candidate) != candidate:
        raise InvalidEnvironment
    components = tuple(candidate[len(prefix) :].split("/"))
    if not components or any(component in ("", ".", "..") for component in components):
        raise InvalidEnvironment
    return components


def directory_identity(metadata):
    if not stat.S_ISDIR(metadata.st_mode):
        raise InvalidEnvironment
    return metadata.st_dev, metadata.st_ino


def file_identity(metadata):
    if (
        not stat.S_ISREG(metadata.st_mode)
        or metadata.st_nlink != 1
        or metadata.st_size > LIMIT
    ):
        raise InvalidEnvironment
    return (
        metadata.st_dev,
        metadata.st_ino,
        metadata.st_mode,
        metadata.st_nlink,
        metadata.st_size,
        metadata.st_mtime_ns,
        metadata.st_ctime_ns,
    )


def open_directory(path, directory_fd=None):
    try:
        if directory_fd is None:
            descriptor = os.open(path, DIRECTORY_FLAGS)
        else:
            descriptor = os.open(path, DIRECTORY_FLAGS, dir_fd=directory_fd)
        directory_identity(os.fstat(descriptor))
        return descriptor
    except (OSError, InvalidEnvironment) as error:
        try:
            os.close(descriptor)
        except (NameError, OSError):
            pass
        raise InvalidEnvironment from error


def is_malformed_supported_line(line):
    for key in KEYS:
        if line == key or (line.startswith(key) and line[len(key) : len(key) + 1] in (" ", "\t")):
            return True
        prefix = "export " + key
        if line == prefix or line.startswith(prefix + "=") or line.startswith(prefix + " ") or line.startswith(prefix + "\t"):
            return True
    return False


def read_environment(directory_fd, descriptors):
    try:
        descriptor = os.open(".env", FILE_FLAGS, dir_fd=directory_fd)
    except FileNotFoundError:
        return None
    except OSError as error:
        raise InvalidEnvironment from error
    descriptors.append(descriptor)

    try:
        before = file_identity(os.fstat(descriptor))
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
        after = file_identity(os.fstat(descriptor))
        if after != before:
            raise InvalidEnvironment
        verification = os.open(".env", FILE_FLAGS, dir_fd=directory_fd)
        try:
            if file_identity(os.fstat(verification)) != after:
                raise InvalidEnvironment
        finally:
            os.close(verification)
    except (OSError, InvalidEnvironment) as error:
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
        raw_value = line[len(key) + 1 :]
        value = raw_value
        if raw_value.startswith(("'", '"')):
            quote = raw_value[0]
            if not raw_value.endswith(quote):
                raise InvalidEnvironment
            bindings = tuple(parse_stream(StringIO(line + "\n")))
            if (
                len(bindings) != 1
                or bindings[0].error
                or bindings[0].key != key
                or not isinstance(bindings[0].value, str)
            ):
                raise InvalidEnvironment
            value = bindings[0].value
        if "\r" in value or "\n" in value:
            raise InvalidEnvironment
        values[key] = value
    return next((values[key] for key in KEYS if values.get(key)), None)


def verify_directories(descriptors, components):
    verification = open_directory(ROOT)
    try:
        if directory_identity(os.fstat(verification)) != directory_identity(os.fstat(descriptors[0])):
            raise InvalidEnvironment
    finally:
        os.close(verification)
    for index, component in enumerate(components):
        verification = open_directory(component, descriptors[index])
        try:
            if directory_identity(os.fstat(verification)) != directory_identity(
                os.fstat(descriptors[index + 1])
            ):
                raise InvalidEnvironment
        finally:
            os.close(verification)


def resolve_token(active_home):
    descriptors = []
    components = home_components(active_home)
    try:
        root_descriptor = open_directory(ROOT)
        descriptors.append(root_descriptor)
        active_descriptor = root_descriptor
        for component in components:
            active_descriptor = open_directory(component, active_descriptor)
            descriptors.append(active_descriptor)

        directories = [active_descriptor]
        if active_descriptor != root_descriptor:
            directories.append(root_descriptor)
        token = None
        for directory in directories:
            token = read_environment(directory, descriptors)
            if token is not None:
                break
        verify_directories(descriptors, components)
        return token
    finally:
        close_failed = False
        for descriptor in reversed(descriptors):
            try:
                os.close(descriptor)
            except OSError:
                close_failed = True
        if close_failed:
            raise InvalidEnvironment


def fail(message):
    try:
        os.close(SAVED_STDIN)
    except OSError:
        pass
    sys.stderr.write(message + "\n")
    return 1


def terminate_for_signal(signum, _frame):
    os._exit(128 + signum)


def reap_inherited_children():
    while True:
        try:
            os.waitpid(-1, 0)
        except ChildProcessError:
            return


def main():
    for signum in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
        signal.signal(signum, terminate_for_signal)
    reap_inherited_children()
    try:
        token = resolve_token(os.environ.get("HERMES_HOME", ""))
    except InvalidEnvironment:
        return fail(INVALID_MESSAGE)
    if token is None:
        return fail(MISSING_MESSAGE)

    try:
        os.dup2(SAVED_STDIN, 0)
        os.close(SAVED_STDIN)
    except OSError:
        return fail(INVALID_MESSAGE)

    environment = os.environ.copy()
    environment.pop("GITHUB_PERSONAL_ACCESS_TOKEN", None)
    environment.pop("GITHUB_TOKEN", None)
    environment["GH_TOKEN"] = token
    try:
        os.execve("/usr/bin/gh", ["/usr/bin/gh", *sys.argv[1:]], environment)
    except OSError:
        return fail(INVALID_MESSAGE)


raise SystemExit(main())
PY
