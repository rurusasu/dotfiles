"""Runtime contracts for the installer's bounded terminal display."""

import errno
import fcntl
import importlib.util
import io
import os
import pty
import re
import select
import shlex
import shutil
import signal
import struct
import subprocess
import sys
import tempfile
import termios
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/python/install_display.py"
HELPER = ROOT / "scripts/sh/install-display.sh"


class Screen:
    """Interpret the small ANSI vocabulary emitted by the panel, not its model."""

    def __init__(self):
        self.rows = [""]
        self.row = 0
        self.col = 0

    def feed(self, text):
        for part in re.split(r"(\x1b\[[0-9;?]*[A-Za-z])", text):
            if part.startswith("\x1b["):
                count = (
                    int(part[2:-1] or "1") if ";" not in part and "?" not in part else 1
                )
                if part.endswith("A"):
                    self.row = max(0, self.row - count)
                elif part.endswith("J"):
                    self.rows[self.row :] = [self.rows[self.row][: self.col]]
                elif part.endswith("K"):
                    self.rows[self.row] = (
                        "" if part == "\x1b[2K" else self.rows[self.row][: self.col]
                    )
                continue
            for char in part:
                if char == "\r":
                    self.col = 0
                elif char == "\n":
                    self.row += 1
                    if self.row == len(self.rows):
                        self.rows.append("")
                else:
                    line = self.rows[self.row].ljust(self.col)
                    self.rows[self.row] = line[: self.col] + char + line[self.col + 1 :]
                    self.col += 1

    @property
    def text(self):
        return "\n".join(self.rows)


class DisplayTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location("install_display", SCRIPT)
        cls.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.module)

    def make_display(self, columns=80, rows=24):
        output = io.StringIO()
        return self.module.Display(output, lambda: (columns, rows)), output

    def screen(self, output):
        screen = Screen()
        screen.feed(output.getvalue())
        return screen.text

    def test_completion_replaces_heading_instead_of_appending(self):
        display, output = self.make_display()
        display.feed(b"[RUNNING] Apple tools\n  Check tools.\n")
        before = self.screen(output)
        self.assertIn("[RUNNING] Apple tools", before)
        display.feed(b"[DONE] Apple tools\n")
        after = self.screen(output)
        self.assertNotIn("[RUNNING]", after)
        self.assertEqual(after.count("[DONE] Apple tools"), 1)
        self.assertEqual(before.index("[RUNNING]"), after.index("[DONE]"))

    def test_long_output_is_bounded_and_partial_prompt_is_visible(self):
        display, output = self.make_display()
        display.feed(b"[RUNNING] Download\n  Fetch sources.\n")
        for i in range(100):
            display.feed(f"line {i}\n".encode())
        display.feed(b"Password: ")
        screen = self.screen(output)
        self.assertIn("[RUNNING] Download", screen)
        self.assertIn("line 99", screen)
        self.assertIn("Password: ", screen)
        self.assertNotIn("line 0\n", screen)
        self.assertLessEqual(len(screen.splitlines()), 8)

    def test_failure_keeps_recent_error_and_replaces_running(self):
        display, output = self.make_display()
        display.feed(b"[RUNNING] Download\n  Fetch sources.\nnetwork failure\n")
        display.feed(b"[FAILED] Download (exit 37)\n")
        self.assertNotIn("[RUNNING]", self.screen(output))
        self.assertIn("[FAILED] Download (exit 37)", self.screen(output))
        self.assertIn("network failure", self.screen(output))

    def test_nested_phases_leave_only_completed_headings(self):
        display, output = self.make_display()
        display.feed(b"[RUNNING] Workflow\n  Run tasks.\n[RUNNING] Child\n  Work.\n")
        display.feed(
            b"[DONE] Child\n[RUNNING] Next\n  Work.\n[DONE] Next\n[DONE] Workflow\n"
        )
        screen = self.screen(output)
        self.assertNotIn("[RUNNING]", screen)
        for title in ("Child", "Next", "Workflow"):
            self.assertEqual(screen.count("[DONE] " + title), 1)

    def test_nested_failure_preserves_child_identity_and_parent_description(self):
        display, output = self.make_display()
        display.feed(
            b"[RUNNING] Outer\n  Run workflow.\n[RUNNING] Inner\n  Download sources.\nnetwork failure\n"
        )
        display.feed(b"[FAILED] Inner (exit 37)\n[FAILED] Outer (exit 37)\n")
        screen = self.screen(output)
        self.assertIn("[FAILED] Inner (exit 37)\n  Download sources.", screen)
        self.assertIn("[FAILED] Outer (exit 37)\n  Run workflow.", screen)
        self.assertNotIn("[RUNNING]", screen)

    def test_fragmented_ansi_unicode_and_carriage_return(self):
        display, output = self.make_display()
        for byte in "\x1b[1m[RUNNING] Test\x1b[0m\n  Work.\nold progress\r\x1b[2K新しい\x1b]0;title\x07".encode():
            display.feed(bytes([byte]))
        screen = self.screen(output)
        self.assertIn("新しい", screen)
        self.assertNotIn("old progress", screen)
        self.assertNotIn("title", screen)

    def test_narrow_screen_never_wraps_panel(self):
        display, output = self.make_display(columns=20, rows=6)
        display.feed(
            ("[RUNNING] " + "界" * 80 + "\n  Description.\n" + "output\n" * 30).encode()
        )
        screen = self.screen(output)
        self.assertLessEqual(len(screen.splitlines()), 5)
        for line in screen.splitlines():
            self.assertLessEqual(sum(2 if c == "界" else 1 for c in line), 19)

    def test_output_outside_phases_is_not_folded(self):
        display, output = self.make_display()
        display.feed(b"Usage: installer\n" + b"help option\n" * 12)
        screen = self.screen(output)
        self.assertIn("Usage: installer", screen)
        self.assertEqual(screen.count("help option"), 12)


class RelayTests(unittest.TestCase):
    def run_terminal(
        self,
        command,
        input_when=None,
        input_bytes=b"",
        extra_env=None,
        launcher=False,
        resize_to=None,
        job_control=False,
        terminate_suspended=0,
    ):
        with tempfile.TemporaryDirectory() as directory:
            pid, fd = pty.fork()
            if pid == 0:
                os.environ.update(
                    TERM="xterm-256color", DOTFILES_INSTALL_LOG_DIR=directory
                )
                os.environ.pop("NO_COLOR", None)
                os.environ.pop("DOTFILES_LIVE_DISPLAY", None)
                os.environ.update(extra_env or {})
                os.environ["DOTFILES_TEST_JOB_CONTROL"] = str(int(job_control))
                os.environ["DOTFILES_TEST_TERMINATE"] = str(terminate_suspended)
                arguments = [sys.executable, str(SCRIPT), "--", "bash", "-euc", command]
                if launcher:
                    arguments = [
                        "bash",
                        "-euc",
                        f'source "{HELPER}"; dotfiles_display_exec bash -euc "$1"; exec bash -euc "$1"',
                        "launcher",
                        command,
                    ]
                os.execl(
                    sys.executable,
                    sys.executable,
                    "-c",
                    """import os, signal, subprocess, sys, termios, time
before = termios.tcgetattr(0)
if os.environ["DOTFILES_TEST_JOB_CONTROL"] == "1":
    signal.signal(signal.SIGTTOU, signal.SIG_IGN)
    def foreground():
        os.setpgrp()
        os.tcsetpgrp(0, os.getpgrp())
    child = subprocess.Popen(sys.argv[1:], preexec_fn=foreground)
    try:
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            waited, state = os.waitpid(child.pid, os.WNOHANG | os.WUNTRACED)
            if waited:
                break
            time.sleep(0.01)
        else:
            raise AssertionError("relay did not suspend")
        assert os.WIFSTOPPED(state), state
        os.tcsetpgrp(0, os.getpgrp())
        suspended = termios.tcgetattr(0)
        expected = list(before)
        suspended[3] &= ~getattr(termios, "PENDIN", 0)
        expected[3] &= ~getattr(termios, "PENDIN", 0)
        assert suspended == expected, (suspended, expected)
        print("TERMINAL_SUSPENDED", flush=True)
        terminate = int(os.environ["DOTFILES_TEST_TERMINATE"])
        if terminate:
            os.killpg(child.pid, terminate)
        else:
            os.tcsetpgrp(0, child.pid)
        os.killpg(child.pid, signal.SIGCONT)
        status = child.wait(timeout=5)
    finally:
        if child.poll() is None:
            os.killpg(child.pid, signal.SIGKILL)
            child.wait()
        os.tcsetpgrp(0, os.getpgrp())
else:
    status = subprocess.call(sys.argv[1:])
after = termios.tcgetattr(0)
# Darwin sets this transient kernel flag when leaving raw mode, even for
# a bare tty.setraw()/tcsetattr() pair. Compare all actual terminal settings.
before[3] &= ~getattr(termios, "PENDIN", 0)
after[3] &= ~getattr(termios, "PENDIN", 0)
assert before == after, (before, after)
print("TERMINAL_RESTORED", flush=True)
sys.exit(status)
""",
                    *arguments,
                )
            fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
            os.set_blocking(fd, False)
            output = bytearray()
            queued_input = b""
            sent = False
            deadline = time.monotonic() + 12
            try:
                while time.monotonic() < deadline:
                    ready, writable, _ = select.select(
                        [fd], [fd] if queued_input else [], [], 0.1
                    )
                    if writable:
                        try:
                            queued_input = queued_input[
                                os.write(fd, queued_input[:4096]) :
                            ]
                        except BlockingIOError:
                            pass
                    if not ready:
                        continue
                    try:
                        chunk = os.read(fd, 65536)
                    except OSError as error:
                        if error.errno != errno.EIO:
                            raise
                        break
                    if not chunk:
                        break
                    output.extend(chunk)
                    if input_when and input_when in output and not sent:
                        if resize_to:
                            fcntl.ioctl(
                                fd,
                                termios.TIOCSWINSZ,
                                struct.pack("HHHH", *resize_to, 0, 0),
                            )
                        queued_input = input_bytes
                        sent = True
                else:
                    self.fail("terminal relay hung: " + repr(output[-1000:]))
            finally:
                os.close(fd)
                waited, status = os.waitpid(pid, os.WNOHANG)
                if not waited:
                    os.killpg(pid, signal.SIGKILL)
                    _, status = os.waitpid(pid, 0)
            logs = list(Path(directory).glob("*.log"))
            contents = b"".join(path.read_bytes() for path in logs)
            for path in logs:
                self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertIn(b"TERMINAL_RESTORED", output)
            return os.waitstatus_to_exitcode(status), bytes(output), contents

    def test_real_tty_hidden_input_state_and_full_log(self):
        command = f'''
source "{HELPER}"
dotfiles_display_init
work() {{
  test -t 0; test -t 1; test -t 2
  printf 'Password: '
  read -rs answer
  test "$answer" = 'private-input'
  printf '\\n'
  for ((i=0; i<100; i++)); do echo "log-$i"; done
  changed=yes
}}
dotfiles_step 'Interactive operation' 'Work with native input.' work
test "$changed" = yes
'''
        status, output, log = self.run_terminal(
            command, b"Password:", b"private-input\n"
        )
        self.assertEqual(status, 0, output)
        self.assertIn(b"Full log:", output)
        self.assertIn(b"log-0", log)
        self.assertIn(b"log-99", log)
        self.assertNotIn(b"private-input", log)
        self.assertNotIn(b"private-input", output)
        screen = Screen()
        screen.feed(output.decode())
        self.assertNotIn("[RUNNING]", screen.text)
        self.assertEqual(screen.text.count("[DONE] Interactive operation"), 1)

    def test_command_failure_and_interrupt_preserve_exit_status(self):
        for action, input_when, input_bytes, expected in [
            ("bash -c 'exit 37'", None, b"", 37),
            ("bash -c 'echo WAITING; sleep 30'", b"WAITING", b"\x03", 130),
        ]:
            with self.subTest(expected=expected):
                command = f'source "{HELPER}"; dotfiles_display_init; dotfiles_step Operation Work bash -c {shlex.quote(action)}'
                status, output, log = self.run_terminal(
                    command, input_when, input_bytes
                )
                self.assertEqual(status, expected, output)
                self.assertIn(b"Full log:", output)
                self.assertNotIn(b"[DONE] Operation", log)

    def test_launcher_wraps_once_and_preserves_command_arguments(self):
        command = f'source "{HELPER}"; dotfiles_display_exec false; dotfiles_display_init; dotfiles_step "A title with spaces" Work printf "%s\\n" "argument with spaces"'
        status, output, log = self.run_terminal(command, launcher=True)
        self.assertEqual(status, 0, output)
        self.assertEqual(output.count(b"Full log:"), 1)
        self.assertIn(b"argument with spaces", log)

    def test_suspend_restores_terminal_and_resumes_input(self):
        for setup, suspend_byte in [("", b"\x1a"), ("stty susp '^Y';", b"\x19")]:
            with self.subTest(suspend_byte=suspend_byte):
                status, output, log = self.run_terminal(
                    setup + "echo READY; read -r answer; test \"$answer\" = continue; echo RESUMED",
                    b"READY",
                    suspend_byte + b"continue\n",
                    job_control=True,
                )
                self.assertEqual(status, 0, output)
                self.assertIn(b"TERMINAL_SUSPENDED", output)
                self.assertIn(b"RESUMED", log)

    def test_raw_child_receives_literal_suspend_character(self):
        child = "import os, tty; tty.setraw(0); print('READY', flush=True); assert os.read(0, 1) == b'\\x1a'"
        status, output, _ = self.run_terminal(
            f"{shlex.quote(sys.executable)} -c {shlex.quote(child)}",
            b"READY",
            b"\x1a",
        )
        self.assertEqual(status, 0, output)

    def test_external_suspend_signal_restores_terminal(self):
        status, output, log = self.run_terminal(
            'kill -TSTP "$PPID"; sleep 0.1; echo RESUMED',
            job_control=True,
        )
        self.assertEqual(status, 0, output)
        self.assertIn(b"TERMINAL_SUSPENDED", output)
        self.assertIn(b"RESUMED", log)

    def test_terminating_suspended_job_reaps_child_without_foregrounding(self):
        for signum in (signal.SIGTERM, signal.SIGHUP):
            with self.subTest(signum=signum):
                status, output, log = self.run_terminal(
                    'echo CHILD:$$; echo READY; sleep 30',
                    b"READY",
                    b"\x1a",
                    job_control=True,
                    terminate_suspended=signum,
                )
                self.assertEqual(status, 128 + signum, output)
                self.assertIn(b"TERMINAL_SUSPENDED", output)
                child_pid = int(re.search(rb"CHILD:(\d+)", log).group(1))
                with self.assertRaises(ProcessLookupError):
                    os.kill(child_pid, 0)

    def test_completion_after_output_without_newline(self):
        command = f'source "{HELPER}"; dotfiles_display_init; dotfiles_step Example Work printf partial'
        status, output, _ = self.run_terminal(command)
        self.assertEqual(status, 0, output)
        screen = Screen()
        screen.feed(output.decode())
        self.assertIn("[DONE] Example", screen.text)
        self.assertNotIn("[RUNNING]", screen.text)

    def test_large_paste_does_not_block_output_drain(self):
        child = """import os, signal, time, tty
signal.alarm(5)
tty.setraw(0)
os.write(1, b"READY\\n")
time.sleep(0.1)
os.write(1, b"x" * 200000)
remaining = 20000
while remaining:
    remaining -= len(os.read(0, remaining))
os.write(1, b"\\nALL_INPUT_RECEIVED\\n")
"""
        status, output, log = self.run_terminal(
            f"{shlex.quote(sys.executable)} -c {shlex.quote(child)}",
            b"READY",
            b"a" * 20000,
        )
        self.assertEqual(status, 0, output[-2000:])
        self.assertIn(b"ALL_INPUT_RECEIVED", log)
        self.assertEqual(log.count(b"x"), 200000)

    def test_launcher_plain_modes_do_not_create_a_log_or_emit_cursor_codes(self):
        command = (
            f'source "{HELPER}"; dotfiles_display_init; dotfiles_step Example Work true'
        )
        for env in ({"NO_COLOR": ""}, {"TERM": "dumb"}):
            with self.subTest(env=env):
                status, output, log = self.run_terminal(
                    command, extra_env=env, launcher=True
                )
                self.assertEqual(status, 0, output)
                self.assertNotIn(b"\x1b", output)
                self.assertIn(b"[DONE] Example", output)
                self.assertEqual(log, b"")

    def test_missing_python_falls_back_without_running_the_wrapped_command_twice(self):
        with tempfile.TemporaryDirectory() as directory:
            Path(directory, "bash").symlink_to(shutil.which("bash"))
            status, output, log = self.run_terminal(
                "echo FALLBACK", extra_env={"PATH": directory}, launcher=True
            )
        self.assertEqual(status, 0, output)
        self.assertEqual(output.count(b"FALLBACK"), 1)
        self.assertEqual(log, b"")

    def test_resize_reaches_child_terminal(self):
        status, output, log = self.run_terminal(
            "stty size; echo BEFORE-RESIZE; read -r answer; sleep 0.1; stty size",
            b"BEFORE-RESIZE",
            b"continue\n",
            resize_to=(16, 44),
        )
        self.assertEqual(status, 0, output)
        self.assertIn(b"24 80", log)
        self.assertIn(b"16 44", log)

    def test_redirected_output_remains_plain_and_preserves_status(self):
        result = subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "--",
                "bash",
                "-c",
                "echo stdout; echo stderr >&2; exit 23",
            ],
            capture_output=True,
            check=False,
        )
        self.assertEqual(result.returncode, 23, result.stderr)
        self.assertEqual(result.stdout, b"stdout\n")
        self.assertEqual(result.stderr, b"stderr\n")


if __name__ == "__main__":
    unittest.main()
