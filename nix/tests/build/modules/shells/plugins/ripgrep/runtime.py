"""Run generated rfg through real rg/fzf and a recording, validating Vim launcher."""

import fcntl
import json
import os
import re
import select
import signal
import struct
import subprocess
import sys
import tempfile
import termios
import time
from pathlib import Path


def check(init, zsh, vim):
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        # Load only the generated public function, avoiding unrelated login hooks.
        function = re.search(r"(?ms)^ *rfg\(\) \{\n.*?^ *\}\n", Path(init).read_text())
        assert function, "Generated rfg function missing"
        source = root / "rfg.zsh"
        source.write_text(function.group())
        editor = root / "editor"
        editor.write_text(
            f"#!{sys.executable}\n"
            + r"""
import json, os, subprocess, sys
from pathlib import Path
args = sys.argv[1:]
Path(os.environ["RFG_ARGS_FILE"]).write_text(json.dumps(args))
assert len(args) == 3 and args[0] == "+2" and args[1] == "--"
subprocess.run([os.environ["RFG_VIM"], "-Nu", "NONE", "-n", "-es", args[0],
                "-c", "call writefile([string(line('.'))], $RFG_CURSOR_FILE) | qa!",
                *args[1:]], check=True)
"""
        )
        editor.chmod(0o700)
        for number, name in enumerate(
            ("+note:call Bogus:tail\ncontinued\n", "-leading.txt", "plain.txt")
        ):
            (root / name).write_text(f"header\nneedle-{number}\n")
            arguments = root / f"args-{number}.json"
            cursor = root / f"cursor-{number}"
            environment = dict(
                os.environ,
                TERM="xterm",
                SHELL=zsh,
                EDITOR=str(editor),
                RFG_ARGS_FILE=str(arguments),
                RFG_CURSOR_FILE=str(cursor),
                RFG_VIM=vim,
            )
            for key in (
                "RIPGREP_CONFIG_PATH",
                "FZF_DEFAULT_OPTS",
                "FZF_DEFAULT_COMMAND",
            ):
                environment.pop(key, None)
            master, slave = os.openpty()
            fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 100, 0, 0))

            def terminal():
                os.setsid()
                fcntl.ioctl(0, termios.TIOCSCTTY, 0)

            with subprocess.Popen(
                [
                    zsh,
                    "-dfc",
                    'source "$1"; rfg "$2"',
                    "rfg-check",
                    str(source),
                    f"needle-{number}",
                ],
                cwd=root,
                env=environment,
                stdin=slave,
                stdout=slave,
                stderr=slave,
                preexec_fn=terminal,
            ) as process:
                os.close(slave)
                output = b""
                entered = False
                deadline = time.monotonic() + 20
                try:
                    while process.poll() is None:
                        assert time.monotonic() < deadline, output.decode(
                            errors="replace"
                        )
                        if select.select([master], [], [], 0.1)[0]:
                            try:
                                chunk = os.read(master, 65536)
                            except OSError:
                                break
                            if not chunk:
                                break
                            output += chunk
                            visible = re.sub(rb"\x1b\[[0-?]*[ -/]*[@-~]", b"", output)
                            if not entered and b"1/1" in visible:
                                os.write(master, b"\r")
                                entered = True
                    assert process.wait(timeout=5) == 0, output.decode(errors="replace")
                finally:
                    if process.poll() is None:
                        os.killpg(process.pid, signal.SIGKILL)
                        process.wait(timeout=5)
                    os.close(master)
            assert json.loads(arguments.read_text()) == ["+2", "--", name]
            assert cursor.read_text().strip() == "2"
        print(
            "rfg preserves colon/newline/option-like filenames through rg, fzf and Vim"
        )


if __name__ == "__main__":
    check(*sys.argv[1:])
