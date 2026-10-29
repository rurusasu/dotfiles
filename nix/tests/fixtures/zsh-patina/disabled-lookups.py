"""Check skipped filesystem work without changing highlighting results."""

import os
from pathlib import Path
import re
import signal
import socket
import subprocess
import sys
import tempfile
import time


CALLABLE = "unique_disabled_callable"


def highlight(sock, fixture, command):
    payload = (
        "VER=3\nCOL=120\nROW=40\n"
        f"CUR={len(command)}\nPRL=0\nLNS=1\nPWD={fixture}\nACD=1\n\n{command}\n"
    )
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        connection.settimeout(5)
        connection.connect(str(sock))
        connection.sendall(payload.encode())
        response = bytearray()
        while chunk := connection.recv(4096):
            response.extend(chunk)
        assert b"?CMD=" not in response, "disabled callable lookup requested shell resolution"
        return response.decode()


def probe(binary, root, fixture):
    runtime = root / "runtime"
    runtime.mkdir(mode=0o700)
    config = root / "config.toml"
    config.write_text('[highlighting]\ndynamic = { callables = false, paths = "complete" }\n')
    env = dict(os.environ, XDG_RUNTIME_DIR=str(runtime), ZSH_PATINA_CONFIG_PATH=str(config))
    sock = runtime / "zsh-patina" / "daemon.sock"
    trace = root / "trace.log"
    with (root / "daemon.log").open("wb") as log:
        process = subprocess.Popen(
            [
                "strace", "-f", "-s", "512", "-o", str(trace),
                "-e", "trace=statx,newfstatat,readlink,readlinkat",
                binary, "start", "--no-daemon",
            ],
            env=env, stdout=log, stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        try:
            deadline = time.monotonic() + 10
            while not sock.exists():
                if process.poll() is not None:
                    raise RuntimeError((root / "daemon.log").read_text())
                if time.monotonic() > deadline:
                    raise TimeoutError("isolated daemon did not start")
                time.sleep(0.02)
            responses = [highlight(sock, fixture, command) for command in (
                CALLABLE, CALLABLE + " existing.txt",
            )]
        finally:
            try:
                if sock.exists():
                    subprocess.run([binary, "stop"], env=env, check=True, timeout=10,
                                   stdout=subprocess.DEVNULL)
            finally:
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
                    raise
    # The supported stop command terminates the foreground daemon with SIGTERM.
    assert process.returncode in (0, -signal.SIGTERM, 128 + signal.SIGTERM), (
        process.returncode, (root / "daemon.log").read_text()
    )
    calls = [line for line in trace.read_text().splitlines()
             if re.search(r"\b(statx|newfstatat)\(", line)]
    return responses, sum(str(fixture / CALLABLE) in line for line in calls), sum(
        str(fixture / "existing.txt") in line for line in calls
    )


def main():
    original, patched = sys.argv[1:]
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        fixture = root / "fixture"
        fixture.mkdir()
        (fixture / "existing.txt").write_text("fixture\n")
        results = []
        for name, binary in (("original", original), ("patched", patched)):
            case = root / name
            case.mkdir()
            results.append(probe(binary, case, fixture))
        baseline, fixed = results
        assert baseline[1] == 2, f"baseline no longer reproduces disabled lookups: {baseline[1]}"
        assert fixed[1] == 0, f"disabled callable still caused filesystem lookups: {fixed[1]}"
        assert baseline[2] == fixed[2] == 1, "existing path lookup was lost or duplicated"
        assert baseline[0] == fixed[0], "highlighting output changed"
        start = len(CALLABLE) + 1
        assert f"{start} {start + len('existing.txt')} underline\n" in fixed[0][1]
        print("Both guard sites skip disabled lookups; highlighting and existing path detection are unchanged.")


if __name__ == "__main__":
    main()
