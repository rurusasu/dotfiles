"""Bounded installer output, with a real child terminal and private full log."""

import codecs
import errno
import fcntl
import os
import pty
import re
import select
import signal
import sys
import tempfile
import termios
import time
import tty
import unicodedata
from collections import deque

PHASE = re.compile(r"^\[(RUNNING|DONE|FAILED)\] (.+)$")


def clipped(text, columns):
    result = []
    width = 0
    for char in text:
        size = (
            0
            if unicodedata.combining(char)
            else 2
            if unicodedata.east_asian_width(char) in "WF"
            else 1
        )
        if width + size > columns:
            break
        result.append(char)
        width += size
    return "".join(result)


class Display:
    """Render only our own short panel; never move into arbitrary child output."""

    def __init__(self, output, size):
        self.output = output
        self.size = size
        self.height = 0
        self.phases = []
        self.logs = deque(maxlen=5)
        self.errors = deque(maxlen=20)
        self.line = []
        self.column = 0
        self.escape = ""
        self.decoder = codecs.getincrementaldecoder("utf-8")("replace")

    def render(self, lines):
        columns, rows = self.size()
        # Leave a spare row: the final newline must not scroll the heading away.
        lines = lines[: max(1, rows - 1)]
        if self.height:
            self.output.write(f"\r\x1b[{min(self.height, max(1, rows - 1))}A\x1b[J")
        for index, line in enumerate(lines):
            style = "\x1b[1m" if index == 0 and line.startswith("[") else "\x1b[2m"
            self.output.write(
                style + clipped(line, max(1, columns - 1)) + "\x1b[0m\r\n"
            )
        self.output.flush()
        self.height = len(lines)

    def redraw(self):
        lines = []
        if self.phases:
            phase = self.phases[-1]
            lines.append(f"[{phase['state']}] {phase['title']}")
            if phase["description"]:
                lines.append(phase["description"])
        tail = list(self.logs)
        if self.line:
            tail.append("".join(self.line))
        _, rows = self.size()
        space = max(0, min(5, rows - 1 - len(lines)))
        if space:
            lines.extend(tail[-space:])
        self.render(lines)

    def complete_line(self, line):
        match = PHASE.match(line)
        if match:
            state, title = match.groups()
            if state == "RUNNING":
                if not self.phases:
                    self.errors.clear()
                self.phases.append({"title": title, "state": state, "description": ""})
                self.logs.clear()
            elif state == "DONE":
                self.render([line])
                self.height = 0  # Completed heading now belongs to scrollback.
                self.logs.clear()
                self.errors.clear()
                for index in range(len(self.phases) - 1, -1, -1):
                    if self.phases[index]["title"] == title:
                        del self.phases[index:]
                        break
            else:
                name = re.sub(r" \(exit [0-9]+\)$", "", title)
                match_index = next(
                    (
                        index
                        for index in range(len(self.phases) - 1, -1, -1)
                        if self.phases[index]["title"] == name
                    ),
                    None,
                )
                if match_index is not None:
                    if match_index < len(self.phases) - 1:
                        # The outer workflow also fails after a child adapter's
                        # EXIT trap. Keep the actual failed child in history.
                        self.redraw()
                        self.height = 0
                        self.logs.clear()
                    del self.phases[match_index + 1 :]
                    self.phases[match_index].update(title=title, state=state)
                else:
                    self.phases.append(
                        {"title": title, "state": state, "description": ""}
                    )
            return
        if line.startswith("[ERROR] ") and line not in self.errors:
            # Explicit updater summaries must outlive JSON output and nested
            # failure traps; arbitrary child output stays in the bounded tail.
            self.errors.append(line)
        if not self.phases:
            self.render([line])
            self.height = 0
        elif not self.phases[-1]["description"] and line.startswith("  "):
            self.phases[-1]["description"] = line
        elif line:
            self.logs.append(line)

    def feed(self, data):
        for char in self.decoder.decode(data):
            if self.escape:
                self.escape += char
                if self.escape.startswith("\x1b["):
                    if len(self.escape) > 2 and "@" <= char <= "~":
                        if char == "K":
                            if self.escape == "\x1b[2K":
                                self.line = []
                            else:
                                del self.line[self.column :]
                        self.escape = ""
                elif self.escape.startswith(("\x1b]", "\x1bP")):
                    if char == "\x07" or self.escape.endswith("\x1b\\"):
                        self.escape = ""
                elif len(self.escape) >= 2:
                    self.escape = ""
                # Bound memory for malformed control strings.
                if len(self.escape) > 8192:
                    self.escape = ""
                continue
            if char == "\x1b":
                self.escape = char
            elif char == "\n":
                line = "".join(self.line)
                self.line = []
                self.column = 0
                self.complete_line(line)
            elif char == "\r":
                self.column = 0
            elif char == "\b":
                self.column = max(0, self.column - 1)
            elif char == "\t":
                self.line.extend(" " * (8 - self.column % 8))
                self.column = len(self.line)
            elif char.isprintable() and self.column < 8192:
                if self.column < len(self.line):
                    self.line[self.column] = char
                else:
                    self.line.append(char)
                self.column += 1
        self.redraw()

    def finish(self, status):
        if status and self.phases and self.phases[-1]["state"] == "RUNNING":
            self.phases[-1]["state"] = "FAILED"
            self.phases[-1]["title"] += f" (exit {status})"
        self.redraw()
        self.height = 0
        if status and self.errors:
            # Final diagnostics belong to scrollback, not the live panel. Wrap
            # them without truncation; never change live prompt/input handling.
            columns, _ = self.size()
            for message in ["Installation errors:", *self.errors]:
                while message:
                    part = clipped(message, max(1, columns - 1)) or message[0]
                    self.output.write(part + "\r\n")
                    message = message[len(part) :]
        self.output.write("\x1b[0m")
        self.output.flush()


def terminal_size():
    size = os.get_terminal_size(2)
    return max(2, size.columns), max(3, size.lines)


def run(command):
    if (
        not all(os.isatty(fd) for fd in (0, 1, 2))
        or os.environ.get("TERM", "dumb") == "dumb"
        or "NO_COLOR" in os.environ
    ):
        os.execvp(command[0], command)

    # mkstemp is exclusive and mode 0600, regardless of the user's umask.
    log_fd, log_path = tempfile.mkstemp(
        prefix="dotfiles-install-",
        suffix=".log",
        dir=os.environ.get("DOTFILES_INSTALL_LOG_DIR"),
    )
    saved = termios.tcgetattr(0)
    dimensions = fcntl.ioctl(0, termios.TIOCGWINSZ, b"\0" * 8)
    pid, master = pty.fork()
    if pid == 0:
        os.close(log_fd)
        termios.tcsetattr(0, termios.TCSANOW, saved)
        fcntl.ioctl(0, termios.TIOCSWINSZ, dimensions)
        os.environ["DOTFILES_LIVE_DISPLAY"] = "1"
        os.execvp(command[0], command)

    display = Display(sys.stderr, terminal_size)
    old_handlers = {}
    status = None
    last_paint = 0.0
    pending = bytearray()
    input_queue = bytearray()
    suspended = False
    suspended_termination = 0

    def forward(signum, _frame):
        nonlocal suspended_termination
        if suspended:
            suspended_termination = signum
        try:
            os.killpg(os.tcgetpgrp(master), signum)
        except ProcessLookupError:
            pass

    def resize(_signum, _frame):
        fcntl.ioctl(
            master, termios.TIOCSWINSZ, fcntl.ioctl(0, termios.TIOCGWINSZ, b"\0" * 8)
        )
        display.redraw()

    def suspend(_signum, _frame):
        nonlocal suspended, status
        if suspended:
            return
        # The nested PTY owns an orphaned session, so its terminal-generated
        # SIGTSTP can be discarded. Stop it explicitly before returning control
        # to the invoking shell, with the real terminal restored.
        groups = {pid, os.tcgetpgrp(master)}
        suspended = True
        try:
            for group in groups:
                try:
                    os.killpg(group, signal.SIGSTOP)
                except ProcessLookupError:
                    pass
            termios.tcsetattr(0, termios.TCSADRAIN, saved)
            sys.stderr.write("\x1b[0m\r\n")
            sys.stderr.flush()
            os.kill(os.getpid(), signal.SIGSTOP)
            # A background resume must not steal input or redraw the shell's UI.
            while not suspended_termination and os.tcgetpgrp(0) != os.getpgrp():
                os.kill(os.getpid(), signal.SIGSTOP)
            if suspended_termination:
                raise SystemExit(128 + suspended_termination)
            tty.setraw(0)
            display.height = 0
            resize(None, None)
        finally:
            suspended = False
            for group in groups:
                try:
                    os.killpg(group, signal.SIGCONT)
                except ProcessLookupError:
                    pass
                except PermissionError:
                    # Darwin can report EPERM for a group containing only an
                    # exited, unreaped child. Do not hide a live group's denial.
                    if not suspended_termination or group != pid or status is not None:
                        raise
                    # Exit/reaping and group removal can settle separately.
                    # Bound the wait, but accept only positive evidence: our
                    # child was reaped AND its group no longer exists.
                    deadline = time.monotonic() + 0.5
                    while time.monotonic() < deadline:
                        if status is None:
                            waited, child_status = os.waitpid(pid, os.WNOHANG)
                            if waited:
                                status = child_status
                        if status is not None:
                            try:
                                os.killpg(group, 0)
                            except ProcessLookupError:
                                break
                            except PermissionError:
                                pass  # A denial is not evidence of exit.
                        time.sleep(0.01)
                    else:
                        raise

    try:
        for signum in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP, signal.SIGQUIT):
            old_handlers[signum] = signal.signal(signum, forward)
        old_handlers[signal.SIGWINCH] = signal.signal(signal.SIGWINCH, resize)
        old_handlers[signal.SIGTSTP] = signal.signal(signal.SIGTSTP, suspend)
        os.set_blocking(master, False)
        tty.setraw(0)
        with os.fdopen(log_fd, "wb", buffering=0) as log:
            log_fd = -1
            while True:
                readers = [master, 0] if len(input_queue) < 65536 else [master]
                ready, writable, _ = select.select(
                    readers, [master] if input_queue else [], [], 0.05
                )
                if master in ready:
                    try:
                        data = os.read(master, 65536)
                    except BlockingIOError:
                        data = None
                    except OSError as error:
                        if error.errno != errno.EIO:
                            raise
                        data = b""
                    if data == b"":
                        break
                    if data:
                        log.write(data)
                        pending.extend(data)
                if 0 in ready:
                    data = os.read(0, 4096)
                    if data:
                        attributes = termios.tcgetattr(master)
                        suspend_char = attributes[6][termios.VSUSP]
                        disabled = bytes([os.fpathconf(master, "PC_VDISABLE")])
                        if (
                            attributes[3] & termios.ISIG
                            and suspend_char != disabled
                            and suspend_char in data
                        ):
                            data = data.replace(suspend_char, b"")
                            suspend(None, None)
                        # Never log input; the child's terminal controls echo.
                        input_queue.extend(data)
                if master in writable:
                    try:
                        count = os.write(master, input_queue[:4096])
                        del input_queue[:count]
                    except BlockingIOError:
                        pass
                    except OSError as error:
                        if error.errno != errno.EIO:
                            raise
                        input_queue.clear()
                if pending and time.monotonic() - last_paint >= 0.05:
                    display.feed(bytes(pending))
                    pending.clear()
                    last_paint = time.monotonic()
                if status is None:
                    waited, child_status = os.waitpid(pid, os.WNOHANG)
                    if waited:
                        status = child_status
                # A daemon may inherit the slave. Drain available output but
                # do not wait forever for an EOF after the installer exits.
                if status is not None and master not in ready:
                    break
            if status is None:
                _, status = os.waitpid(pid, 0)
            code = os.waitstatus_to_exitcode(status)
            code = 128 - code if code < 0 else code
            display.feed(bytes(pending))
            display.finish(code)
            sys.stderr.write(f"Full log: {log_path}\r\n")
            sys.stderr.flush()
            return code
    finally:
        if not suspended_termination:
            termios.tcsetattr(0, termios.TCSADRAIN, saved)
        for signum, handler in old_handlers.items():
            signal.signal(signum, handler)
        os.close(master)
        if log_fd >= 0:
            os.close(log_fd)
        if status is None:
            try:
                os.kill(pid, signal.SIGHUP)
            except ProcessLookupError:
                pass
            os.waitpid(pid, 0)


if __name__ == "__main__":
    arguments = sys.argv[1:]
    if arguments[:1] == ["--"]:
        arguments.pop(0)
    if not arguments:
        sys.exit("usage: install_display.py -- command [args ...]")
    sys.exit(run(arguments))
