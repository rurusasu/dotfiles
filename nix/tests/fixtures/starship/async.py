#!/usr/bin/env python3
"""PTY integration checks for the asynchronous Zsh Starship adapter.

Uses the supplied Starship's standard init, a synthetic renderer, temporary
HOME/config/runtime, and only owned PTY/worker processes. No user environment,
TTY contents, adapter environment keys, or cache keys are logged. Linux /proc
identities protect cleanup from touching unrelated processes.
"""

import argparse
import fcntl
import hashlib
import json
import os
import pathlib
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

PROBE = b"\x1b[97~"
CONTROL = b"\x1b[98~"
CSI = re.compile(rb"\x1b\[[0-?]*[ -/]*[@-~]")

FAKE = r"""
import json, os, pathlib, shlex, sys, time
argv=sys.argv[1:]
if argv and argv[0]=='time': print(int(time.time()*1000)); raise SystemExit(0)
if '--continuation' in argv: print('AF-CONT-%_> ',end=''); raise SystemExit(0)
if '--right' in argv: raise SystemExit(0)
options={}
index=1
while index<len(argv):
    item=argv[index]
    if item.startswith('--') and '=' in item: key,value=item[2:].split('=',1)
    elif item.startswith('--') and index+1<len(argv): key,value=item[2:],argv[index+1]; index+=1
    else: index+=1; continue
    options[key]=value; index+=1
control=json.loads(pathlib.Path(os.environ['AF_CONTROL_JSON']).read_text())
config=pathlib.Path(os.environ.get('STARSHIP_CONFIG','context-none')).stem
cwd=pathlib.Path.cwd().name
pid=os.getpid()
stat=pathlib.Path('/proc/self/stat').read_text(); start=stat[stat.rfind(')')+2:].split()[19]
event={'event':'start','pid':pid,'ppid':os.getppid(),'start_ticks':start,'time_ns':time.monotonic_ns(),
       'label':control['label'],'config':config,'cwd':cwd,'nix_shell':os.environ.get('IN_NIX_SHELL',''),
       'synthetic_padding_bytes':len(os.environ.get('AF_SYNTHETIC_ENV_PADDING','')),
       'args':{key:options.get(key,'') for key in ['terminal-width','keymap','status','pipestatus','cmd-duration','jobs']}}
def log(value):
    fd=os.open(os.environ['AF_LOG'],os.O_WRONLY|os.O_APPEND|os.O_CREAT,0o600)
    os.write(fd,(json.dumps(value,separators=(',',':'))+'\n').encode()); os.close(fd)
log(event)
if control.get('wait_for'):
    gate=pathlib.Path(os.environ['AF_TEST_ROOT'])/control['wait_for']
    while not gate.exists(): time.sleep(0.005)
time.sleep(float(control.get('delay',0.05)))
token='AF-'+control['label']+'-'+config+'-'+cwd+'-W'+options.get('terminal-width','')+'-K'+options.get('keymap','')+'-END'
body='%F{green}'+token+'%f '
if control.get('mode')=='payload':
    testroot=pathlib.Path(os.environ['AF_TEST_ROOT'])
    body+='$(command touch '+shlex.quote(str(testroot/'injected-dollar'))+') '
    body+='`command touch '+shlex.quote(str(testroot/'injected-backtick'))+'` LITERAL%%n '
result=7 if control.get('mode')=='fail' else 0
if result: body='AF-FALLBACK-END '
log({'event':'end','pid':pid,'start_ticks':start,'time_ns':time.monotonic_ns(),'label':control['label'],'result':result})
print(body,end='')
raise SystemExit(result)
"""

OBSERVER = r"""
HISTFILE=/dev/null
zmodload zsh/system
autoload -Uz add-zsh-hook add-zle-hook-widget
typeset -gi __af_seq=0
typeset -gr __af_pid="$sysparams[pid]"
__af_emit() {
  (( ZSH_SUBSHELL == 0 )) || return 0
  [[ $sysparams[pid] == $__af_pid ]] || return 0
  local restored=0 error=0
  [[ ${PROMPT-} == "${__af_original_prompt-}" ]] && restored=1
  [[ -n ${_dsal_error-} ]] && error=1
  (( ++__af_seq ))
  local frame="AF"$'\0'"$1"$'\0'"$__af_seq"$'\0'"${BUFFER-}"$'\0'"${CURSOR:-0}"$'\0'"${PWD:t}"$'\0'"${COLUMNS:-0}"$'\0'"${KEYMAP-}"$'\0'"${CONTEXT-}"$'\0'"${_dsal_visible-}"$'\0'"${_dsal_active:-0}"$'\0'"${_dsal_pending:-0}"$'\0'"${_dsal_enabled:-0}"$'\0'"$restored"$'\0'"$error"$'\0'"${_dsal_worker-}"$'\0'"${STARSHIP_CMD_STATUS-}"$'\0'"${(j:,:)STARSHIP_PIPE_STATUS}"$'\0'
  syswrite -o9 "$frame"
  return 0
}
__af_direnv_precmd() {
  local previous=$?
  [[ -f $AF_ENV_FILE ]] && source "$AF_ENV_FILE"
  return $previous
}
__af_init() { __af_emit INIT; return 0; }
__af_draw() { __af_emit DRAW; return 0; }
__af_probe() {
  case ${_dsal_error-} in
    'could not dispatch Starship job') __af_emit ERROR_DISPATCH;;
    'invalid Starship result token') __af_emit ERROR_TOKEN;;
    'async transport failure ('*) __af_emit ERROR_TRANSPORT;;
    'Starship failed or timed out ('*) __af_emit ERROR_RENDER;;
    'Starship request exceeds safe transport size') __af_emit ERROR_SIZE;;
    'async worker recovery limit reached') __af_emit ERROR_RETRY_LIMIT;;
  esac
  __af_emit PROBE
  return 0
}
__af_control() { source "$AF_ACTION_FILE"; __af_emit CONTROL; return 0; }
__af_emit BEFORE_STANDARD
"""


def identity(pid):
    try:
        proc = pathlib.Path("/proc") / str(pid)
        raw = (proc / "stat").read_text()
        parts = raw[raw.rfind(")") + 2 :].split()
        if parts[0] == "Z":
            return None
        return (pid, parts[19])
    except (FileNotFoundError, ProcessLookupError):
        return None


class Session:
    def __init__(
        self,
        options,
        adapter_bytes,
        control,
        timeout,
        simulate_direnv=False,
        padding_bytes=0,
        long_binary=False,
        observe_async=False,
    ):
        self.root = pathlib.Path(tempfile.mkdtemp(prefix="starship-async-test-"))
        self.padding_bytes = padding_bytes
        adapter = self.root / "adapter-snapshot.zsh"
        adapter.write_bytes(adapter_bytes)
        self.pid = self.fd = self.marker_r = None
        self.frames = []
        self.pending = bytearray()
        self.tty_tail = bytearray()
        self.owned = {}
        self.cleanup_ok = True
        self.closed = False
        self.control_path = self.root / "control.json"
        self.log_path = self.root / "worker-markers.jsonl"
        self.action_path = self.root / "action.zsh"
        self.env_path = self.root / "direnv.zsh"
        for directory in ("home", "runtime", "dir-a", "dir-b", "config"):
            (self.root / directory).mkdir(mode=0o700)
        self.a = self.root / "config/context-A.toml"
        self.b = self.root / "config/context-B.toml"
        self.a.write_text("")
        self.b.write_text("")
        fake = self.root / "fake-starship"
        if long_binary:
            parent = self.root
            for number in range(11):
                parent = parent / (str(number) + "x" * 198)
                parent.mkdir()
            fake = parent / "fake-starship"
        fake.write_text("#!" + sys.executable + "\n" + FAKE)
        fake.chmod(0o700)
        self.configure(**control)
        init = self.root / "standard-init.zsh"
        # Preserve the package's real init hooks and argument handling; replace
        # only the executable with the controlled renderer used by this test.
        init.write_text(options.standard_init.replace(options.starship_path, str(fake)))
        setup = self.root / "setup.zsh"
        adapter_arguments = " ".join(
            shlex.quote(value)
            for value in (
                str(adapter),
                str(fake),
                str(options.async_library),
                str(options.timeout),
                str(timeout),
            )
        )
        # Observe inside the actual callback function without invoking another
        # user widget: probes would themselves break kill/yank chaining.
        async_observer = ""
        if observe_async:
            async_observer = (
                "functions[__af_receive_original]=$functions[_dsal_receive]\n"
                '_dsal_receive() { __af_receive_original "$@"; '
                "__af_emit ASYNC_RECEIVED; return 0; }\n"
            )
        setup.write_text(
            OBSERVER
            + ("\nadd-zsh-hook precmd __af_direnv_precmd\n" if simulate_direnv else "")
            + "\nsource "
            + shlex.quote(str(init))
            + "\n__af_emit AFTER_STANDARD\ntypeset -g __af_original_prompt=$PROMPT\n"
            + "__af_emit BEFORE_ADAPTER\nsource "
            + adapter_arguments
            + "\n__af_emit AFTER_ADAPTER\n"
            + async_observer
            + "zle -N __af_probe\nzle -N __af_control\n"
            + "for map in main emacs viins vicmd; do bindkey -M $map $'\\e[97~' __af_probe; bindkey -M $map $'\\e[98~' __af_control; done\n"
            + "add-zle-hook-widget line-init __af_init\n"
            + "add-zle-hook-widget line-pre-redraw __af_draw\n__af_emit LOADED\n"
        )
        env = {
            "HOME": str(self.root / "home"),
            "ZDOTDIR": str(self.root / "home"),
            "USER": "functional",
            "LOGNAME": "functional",
            "LANG": "en_US.UTF-8",
            "PATH": options.path,
            "TERM": "xterm-256color",
            "XDG_CONFIG_HOME": str(self.root / "config"),
            "XDG_RUNTIME_DIR": str(self.root / "runtime"),
            "STARSHIP_CONFIG": str(self.a),
            "IN_NIX_SHELL": "impure",
            "AF_CONTROL_JSON": str(self.control_path),
            "AF_LOG": str(self.log_path),
            "AF_TEST_ROOT": str(self.root),
            "AF_ACTION_FILE": str(self.action_path),
            "AF_ENV_FILE": str(self.env_path),
        }
        if padding_bytes:
            env["AF_SYNTHETIC_ENV_PADDING"] = "S" * padding_bytes
        read_fd, write_fd = os.pipe()
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            os.close(read_fd)
            if write_fd != 9:
                os.dup2(write_fd, 9, inheritable=True)
                os.close(write_fd)
            else:
                os.set_inheritable(9, True)
            os.chdir(self.root / "dir-a")
            os.execve(options.zsh, [str(options.zsh), "-f", "-i"], env)
        os.close(write_fd)
        self.marker_r = read_fd
        fcntl.ioctl(self.fd, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 120, 0, 0))
        os.write(self.fd, ("source " + shlex.quote(str(setup)) + "\r").encode())
        try:
            self.wait(lambda frame: frame["kind"] == "INIT", timeout=8)
        except (OSError, RuntimeError, ValueError) as exc:
            markers = [frame["kind"] for frame in self.frames][-40:]
            self.close()
            raise RuntimeError(
                type(exc).__name__ + ": synthetic stages=" + ",".join(markers)
            ) from None
        except BaseException:
            self.close()
            raise

    def configure(self, **values):
        temporary = self.root / "control-new.json"
        temporary.write_text(json.dumps(values))
        os.replace(temporary, self.control_path)

    def poll(self, timeout=0.03):
        ready, _, _ = select.select([self.fd, self.marker_r], [], [], max(timeout, 0))
        for fd in ready:
            try:
                data = os.read(fd, 65536)
            except OSError:
                data = b""
            if not data:
                continue
            if fd == self.fd:
                self.tty_tail.extend(data)
                del self.tty_tail[:-8192]
                continue
            self.pending.extend(data)
            while self.pending.count(0) >= 18:
                values = []
                for _ in range(18):
                    position = self.pending.index(0)
                    values.append(
                        bytes(self.pending[:position]).decode("utf-8", "strict")
                    )
                    del self.pending[: position + 1]
                if values[0] != "AF":
                    raise RuntimeError("Invalid synthetic marker framing")
                keys = (
                    "magic",
                    "kind",
                    "seq",
                    "buffer",
                    "cursor",
                    "cwd",
                    "width",
                    "keymap",
                    "context",
                    "visible",
                    "active",
                    "pending",
                    "enabled",
                    "restored",
                    "error",
                    "worker",
                    "status",
                    "pipe",
                )
                frame = dict(zip(keys, values))
                for key in (
                    "seq",
                    "cursor",
                    "width",
                    "active",
                    "pending",
                    "enabled",
                    "restored",
                    "error",
                ):
                    frame[key] = int(frame[key])
                frame["received_ns"] = time.monotonic_ns()
                self.frames.append(frame)

    def wait(self, predicate, timeout=5, since=0):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            for frame in self.frames:
                if frame["received_ns"] >= since and predicate(frame):
                    return frame
            self.poll(min(0.03, max(0, deadline - time.monotonic())))
        markers = sorted({frame["kind"] for frame in self.frames})
        raise TimeoutError("Synthetic state deadline; markers=" + ",".join(markers))

    def observe(self, duration):
        deadline = time.monotonic() + duration
        while time.monotonic() < deadline:
            self.poll(min(0.03, max(0, deadline - time.monotonic())))

    def probe(self):
        sent = time.monotonic_ns()
        os.write(self.fd, PROBE)
        return self.wait(lambda frame: frame["kind"] == "PROBE", since=sent)

    def visible(self, token, timeout=5):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            state = self.probe()
            if token in state["visible"] and state["enabled"]:
                return state
            self.observe(0.03)
        raise TimeoutError("Expected synthetic render was not accepted: " + token)

    def control(self, script):
        temporary = self.root / "action-new.zsh"
        temporary.write_text(script + "\n")
        os.replace(temporary, self.action_path)
        sent = time.monotonic_ns()
        os.write(self.fd, CONTROL)
        return self.wait(lambda frame: frame["kind"] == "CONTROL", since=sent)

    def line(self, text=""):
        sent = time.monotonic_ns()
        os.write(self.fd, text.encode() + b"\r")
        return self.wait(lambda frame: frame["kind"] == "INIT", timeout=8, since=sent)

    def logs(self):
        if not self.log_path.exists():
            return []
        result = []
        for line in self.log_path.read_text().splitlines():
            try:
                result.append(json.loads(line))
            except json.JSONDecodeError:
                continue
        return result

    def fake_start(self, label, timeout=5):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            matches = [
                event
                for event in self.logs()
                if event["event"] == "start" and event["label"] == label
            ]
            if matches:
                return matches[-1]
            self.poll(0.03)
        raise TimeoutError("Synthetic worker did not start")

    def capture_owned(self, pid=None):
        pid = pid or self.pid
        signature = identity(pid)
        if not signature:
            return
        self.owned[pid] = signature
        try:
            children = (
                pathlib.Path("/proc") / str(pid) / "task" / str(pid) / "children"
            ).read_text()
            for child in children.split():
                self.capture_owned(int(child))
        except (FileNotFoundError, ProcessLookupError):
            pass

    def wait_owned_descendants_gone(self, duration=2):
        deadline = time.monotonic() + duration
        while time.monotonic() < deadline:
            alive = [
                pid
                for pid, signature in self.owned.items()
                if pid != self.pid and identity(pid) == signature
            ]
            if not alive:
                return True
            self.poll(0.03)
        return False

    def close(self):
        if self.closed:
            return
        self.closed = True
        if not self.pid:
            shutil.rmtree(self.root)
            return
        self.capture_owned()
        try:
            os.write(self.fd, b"\x03\x15exit\r")
        except OSError:
            pass
        deadline = time.monotonic() + 3
        reaped = False
        while time.monotonic() < deadline:
            try:
                child, _ = os.waitpid(self.pid, os.WNOHANG)
            except ChildProcessError:
                child = self.pid
            if child:
                reaped = True
                break
            self.poll(0.03)
        # A worker can be reparented for a moment after its shell exits while
        # the process-group HUP is still being handled. Check the stable PID
        # identity through a short grace period before classifying a leak.
        deadline = time.monotonic() + 2
        while reaped and time.monotonic() < deadline:
            if not any(
                identity(pid) == signature for pid, signature in self.owned.items()
            ):
                break
            time.sleep(0.01)
        self.cleanup_ok = reaped
        # Only identities captured in this owned PTY tree are eligible for cleanup.
        for pid, signature in reversed(list(self.owned.items())):
            if identity(pid) == signature:
                self.cleanup_ok = False
                try:
                    os.kill(pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
        for fd in (self.fd, self.marker_r):
            try:
                os.close(fd)
            except OSError:
                pass
        self.tty_tail.clear()
        shutil.rmtree(self.root)


def max_active(events):
    active = set()
    maximum = 0
    for event in sorted(events, key=lambda item: item["time_ns"]):
        if event["event"] == "start":
            active.add(event["pid"])
            maximum = max(maximum, len(active))
        else:
            active.discard(event["pid"])
    return maximum


def key_buffer(s, keys, expected, failure):
    """Observe a key through the nolast pre-redraw hook, never a probe widget."""
    sequence = s.frames[-1]["seq"]
    os.write(s.fd, keys)
    predicate = expected if callable(expected) else lambda buffer: buffer == expected
    try:
        return s.wait(
            lambda frame: (
                frame["kind"] == "DRAW"
                and frame["seq"] > sequence
                and predicate(frame["buffer"])
            ),
            timeout=3,
        )
    except TimeoutError:
        raise AssertionError(failure) from None


def release_render(s, label):
    (s.root / "release-render").touch()
    s.wait(
        lambda frame: (
            frame["kind"] == "ASYNC_RECEIVED"
            and "AF-" + label + "-" in frame["visible"]
            and frame["enabled"]
            and not frame["active"]
        ),
        timeout=5,
    )


def check_yank_pop(s):
    s.fake_start("yank-chain")
    setup = (
        "bindkey -e\n"
        "bindkey -M emacs '^Y' yank\n"
        "bindkey -M emacs $'\\ey' yank-pop\n"
        "CUTBUFFER=first\nkillring=(second third)\nBUFFER=''\nCURSOR=0"
    )
    # First prove that the fixture's hooks and bindings preserve normal chaining.
    s.control(setup)
    key_buffer(s, b"\x19", "first", "baseline yank did not insert CUTBUFFER")
    key_buffer(s, b"\x1by", "second", "baseline yank-pop did not cycle killring")
    s.control(setup)
    key_buffer(s, b"\x19", "first", "yank did not insert CUTBUFFER")
    release_render(s, "yank-chain")
    key_buffer(s, b"\x1by", "second", "async callback broke yank-pop chaining")


def check_kill_chain(s):
    s.fake_start("kill-chain")
    original = "alpha beta gamma"
    setup = (
        "bindkey -e\n"
        "bindkey -M emacs $'\\ed' kill-word\n"
        "bindkey -M emacs '^K' kill-line\n"
        "bindkey -M emacs '^Y' yank\n"
        "CUTBUFFER=''\nkillring=(old)\nBUFFER='alpha beta gamma'\nCURSOR=6"
    )
    for asynchronous in (False, True):
        s.control(setup)
        key_buffer(
            s,
            b"\x1bd",
            lambda buffer: buffer.startswith("alpha ") and "beta" not in buffer,
            "kill-word did not remove the synthetic word",
        )
        if asynchronous:
            release_render(s, "kill-chain")
        key_buffer(
            s, b"\x0b", "alpha ", "kill-line did not remove the remaining suffix"
        )
        key_buffer(
            s,
            b"\x19",
            original,
            "async callback broke kill-word/kill-line chaining"
            if asynchronous
            else "baseline kill-word/kill-line did not share one kill buffer",
        )


def check_kill_boundary(s):
    s.fake_start("kill-boundary")
    setup = (
        "bindkey -e\n"
        "bindkey -M emacs '^K' kill-line\n"
        "bindkey -M emacs '^Y' yank\n"
        "CUTBUFFER=old\nkillring=(older)\nBUFFER='alpha beta'\nCURSOR=6"
    )
    for asynchronous in (False, True):
        s.control(setup)
        key_buffer(
            s, b"x", "alpha xbeta", "self-insert did not update the synthetic buffer"
        )
        if asynchronous:
            release_render(s, "kill-boundary")
        key_buffer(
            s, b"\x0b", "alpha x", "kill-line did not remove the synthetic suffix"
        )
        key_buffer(
            s,
            b"\x19",
            "alpha xbeta",
            "async callback falsely merged the old kill buffer after self-insert"
            if asynchronous
            else "baseline self-insert did not break the old kill chain",
        )


def check_accepted(s):
    state = s.visible("AF-normal-")
    assert state["enabled"] and not state["restored"], "candidate did not stay enabled"
    event = s.fake_start("normal")
    assert event["args"]["jobs"] == "0", "internal worker leaked into user job count"
    assert event["synthetic_padding_bytes"] == s.padding_bytes, (
        "worker did not inherit complete synthetic environment"
    )


def check_payload(s):
    s.visible("AF-payload-")
    s.observe(0.15)
    s.probe()
    assert not (s.root / "injected-dollar").exists(), (
        "dollar command substitution was re-evaluated"
    )
    assert not (s.root / "injected-backtick").exists(), (
        "backtick substitution was re-evaluated"
    )
    plain = CSI.sub(b"", bytes(s.tty_tail))
    assert b"LITERAL%n" in plain, "literal percent escapes changed"


def check_empty_refresh(s):
    s.visible("AF-normal-")
    s.configure(label="empty-refresh", delay=0.04)
    s.line()
    s.visible("AF-empty-refresh-")
    assert s.fake_start("empty-refresh")["args"]["status"] == "", (
        "empty prompt refresh retained a command status"
    )


def check_edit(s):
    text = "typed buffer"
    os.write(s.fd, text.encode() + b"\x1b[D\x1b[D")
    before = s.probe()
    assert before["buffer"] == text and before["cursor"] == len(text) - 2, (
        "fixture cursor setup failed"
    )
    s.visible("AF-edit-")
    after = s.probe()
    assert after["buffer"] == text and after["cursor"] == before["cursor"], (
        "async update changed edit state"
    )


def check_status(s):
    s.visible("AF-normal-")
    s.configure(label="status", delay=0.04)
    s.line("builtin false")
    s.visible("AF-status-")
    event = s.fake_start("status")
    assert event["args"]["status"] == "1" and event["args"]["pipestatus"] == "1", (
        "exit status changed"
    )
    s.configure(label="pipeline", delay=0.04)
    s.line("builtin false | builtin true")
    s.visible("AF-pipeline-")
    event = s.fake_start("pipeline")
    assert event["args"]["status"] == "0" and event["args"]["pipestatus"] == "1 0", (
        "pipeline status changed"
    )
    s.configure(label="subshell", delay=0.04)
    s.line("(exit 7)")
    s.visible("AF-subshell-")
    event = s.fake_start("subshell")
    assert event["args"]["status"] == "7" and event["args"]["pipestatus"] == "7", (
        "subshell exit status changed"
    )
    s.configure(label="empty", delay=0.04)
    s.line()
    s.visible("AF-empty-")
    event = s.fake_start("empty")
    assert event["args"]["status"] == "" and event["args"]["pipestatus"] == "", (
        "empty Enter retained old status"
    )
    s.configure(label="failed-status", delay=0.04, mode="fail")
    s.line("builtin false")
    check_failure(s)
    event = s.fake_start("failed-status")
    assert event["args"]["status"] == "1" and event["args"]["pipestatus"] == "1", (
        "fallback lost failed command status"
    )


def check_context(s, change):
    s.fake_start("old")
    s.configure(label="new", delay=0.03)
    if change == "cwd":
        barrier = s.control("builtin cd " + shlex.quote(str(s.root / "dir-b")))
    elif change == "env":
        s.env_path.write_text(
            "export STARSHIP_CONFIG="
            + shlex.quote(str(s.b))
            + "\nexport IN_NIX_SHELL=pure\n"
        )
        barrier = s.line()
    else:
        barrier = s.control("COLUMNS=83\nzle -K vicmd")
    s.visible("AF-new-")
    late = [
        frame
        for frame in s.frames
        if frame["received_ns"] >= barrier["received_ns"]
        and frame["kind"] in ("DRAW", "PROBE")
        and "AF-old-" in frame["visible"]
        and not frame["restored"]
    ]
    assert not late, "old worker render crossed a changed context"
    event = s.fake_start("new")
    if change == "cwd":
        assert event["cwd"] == "dir-b", "worker retained old cwd"
    elif change == "env":
        assert event["config"] == "context-B" and event["nix_shell"] == "pure", (
            "worker retained old environment"
        )
        assert event["synthetic_padding_bytes"] == s.padding_bytes, (
            "environment refresh lost another exported value"
        )
    else:
        assert (
            event["args"]["terminal-width"] == "83"
            and event["args"]["keymap"] == "vicmd"
        ), "worker retained old width/keymap"
    assert max_active(s.logs()) <= 1, "more than one render job ran concurrently"


def check_bounded(s):
    s.fake_start("bounded")
    for _ in range(15):
        s.line()
    s.visible("AF-bounded-")
    s.observe(0.2)
    events = s.logs()
    assert max_active(events) <= 1, "concurrent renders exceeded one"
    assert sum(item["event"] == "start" for item in events) <= 3, (
        "empty Enter created an unbounded job queue"
    )


def check_failure(s):
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        state = s.probe()
        if (
            state["restored"]
            and not state["enabled"]
            and not state["active"]
            and state["error"]
        ):
            return
        s.observe(0.03)
    raise AssertionError("worker failure/timeout did not restore original prompt")


def check_oversized(s):
    check_failure(s)
    assert any(frame["kind"] == "ERROR_SIZE" for frame in s.frames), (
        "oversized fixture did not exercise the transport bound"
    )


def check_retry_limit(s):
    s.fake_start("retry-limit")
    s.capture_owned()
    # Kill only this fixture's named library worker. Enter the ordinary
    # line-init path after each fault while the renderer is still delayed, so
    # no successful callback can reset the same-context recovery budget.
    fault = 'zpty -d "$_dsal_worker"\n(( _dsal_enabled )) && _dsal_line_init'
    first = s.control(fault)
    assert first["enabled"] and first["active"], "first worker failure did not recover"
    deadline = time.monotonic() + 3
    while time.monotonic() < deadline:
        if sum(event["event"] == "start" for event in s.logs()) >= 2:
            break
        s.poll(0.03)
    assert sum(event["event"] == "start" for event in s.logs()) == 2, (
        "first recovery did not start exactly one replacement"
    )
    s.capture_owned()
    s.configure(label="after-retry-limit", delay=0.01)
    second = s.control(fault)
    assert second["restored"] and not second["enabled"] and not second["active"], (
        "repeated worker failure did not fall back"
    )
    s.probe()
    assert any(frame["kind"] == "ERROR_RETRY_LIMIT" for frame in s.frames), (
        "same-context recovery limit was not exercised"
    )
    assert sum(event["event"] == "start" for event in s.logs()) == 2, (
        "repeated failure created more than one replacement"
    )
    assert s.wait_owned_descendants_gone(), (
        "worker recovery left an owned render process running"
    )


def check_restore(s):
    s.fake_start("restore")
    s.capture_owned()
    s.configure(label="after-restore", delay=0.01)
    state = s.control("dsal_restore")
    assert state["restored"] and not state["active"] and not state["pending"], (
        "restore left adapter active"
    )
    assert s.wait_owned_descendants_gone(), (
        "restore leaked an owned worker or render job"
    )


def check_exit(s):
    s.fake_start("exit")
    # A Ctrl-C/new line may synchronously render the original prompt while the
    # shell exits. Its controlled fake should be fast; the in-flight old job
    # retains its six-second delay and must still be cleaned up by the adapter.
    s.configure(label="after-exit", delay=0.01)


def check_continuation(s):
    s.fake_start("continuation")
    os.write(s.fd, b"echo '\r")
    deadline = time.monotonic() + 5
    state = None
    while time.monotonic() < deadline:
        state = s.probe()
        if state["context"] == "cont":
            break
        s.observe(0.03)
    assert state and state["context"] == "cont", (
        "fixture did not enter continuation context"
    )
    count = len(s.frames)
    s.tty_tail.clear()
    s.observe(0.7)
    after = s.probe()
    assert after["context"] == "cont" and after["buffer"] == state["buffer"], (
        "callback changed continuation editing"
    )
    assert b"AF-continuation-" not in s.tty_tail, (
        "callback reset PS2 to the main prompt"
    )
    assert not any(frame["kind"] == "INIT" for frame in s.frames[count:]), (
        "callback restarted continuation editor"
    )
    os.write(s.fd, b"\x03")


def check_continuation_error(s, transport=False):
    s.fake_start("continuation-error")
    os.write(s.fd, b"echo '\r")
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        before = s.probe()
        if before["context"] == "cont":
            break
        s.observe(0.03)
    assert before["context"] == "cont", "fixture did not enter continuation context"
    s.observe(0.05)
    assert b"AF-CONT-quote>" in CSI.sub(b"", bytes(s.tty_tail)), (
        "%_ did not show the quote parser context"
    )
    s.tty_tail.clear()
    event = (
        "_dsal_receive '[async]' 1 ''"
        if transport
        else "_dsal_receive _dsal_render 0 invalid-token"
    )
    after = s.control(event)
    assert after["restored"] and not after["enabled"] and after["error"], (
        "error did not restore the standard prompt"
    )
    assert (
        after["context"] == "cont"
        and after["buffer"] == before["buffer"]
        and after["cursor"] == before["cursor"]
    ), "error fallback changed continuation editing"
    s.observe(0.1)
    assert b"AF-CONT->" not in CSI.sub(b"", bytes(s.tty_tail)), (
        "error fallback lost the %_ parser context"
    )
    assert b"AF-continuation-error-" not in s.tty_tail, (
        "error fallback replaced PS2 with the main prompt"
    )
    os.write(s.fd, b"\x03")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--adapter", type=pathlib.Path, required=True)
    parser.add_argument("--zsh", type=pathlib.Path, required=True)
    parser.add_argument("--starship", type=pathlib.Path, required=True)
    parser.add_argument("--async-library", type=pathlib.Path, required=True)
    parser.add_argument("--timeout", type=pathlib.Path, required=True)
    parser.add_argument(
        "--path",
        required=True,
        help="isolated executable search path supplied by the build",
    )
    parser.add_argument(
        "--case", action="append", help="run only named synthetic cases"
    )
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()
    args.starship_path = str(args.starship.resolve())
    with tempfile.TemporaryDirectory(prefix="starship-init-") as init_home:
        args.standard_init = subprocess.run(
            [args.starship_path, "init", "zsh", "--print-full-init"],
            check=True,
            capture_output=True,
            text=True,
            cwd=init_home,
            env={"HOME": init_home, "PATH": args.path, "LANG": "C.UTF-8"},
        ).stdout
    if args.starship_path not in args.standard_init:
        parser.error(
            "the generated standard init did not reference the supplied executable"
        )
    adapter_bytes = args.adapter.read_bytes()
    adapter_sha256 = hashlib.sha256(adapter_bytes).hexdigest()
    cases = [
        (
            "accepted-render-and-user-jobs",
            check_accepted,
            {"label": "normal", "delay": 0.05},
            2,
        ),
        (
            "large-exported-environment",
            check_accepted,
            {"label": "normal", "delay": 0.05},
            2,
        ),
        (
            "empty-enter-refresh",
            check_empty_refresh,
            {"label": "normal", "delay": 0.05},
            2,
        ),
        (
            "untrusted-render-and-percent",
            check_payload,
            {"label": "payload", "delay": 0.1, "mode": "payload"},
            2,
        ),
        ("buffer-cursor-preservation", check_edit, {"label": "edit", "delay": 0.35}, 2),
        (
            "exit-and-pipeline-status",
            check_status,
            {"label": "normal", "delay": 0.05},
            2,
        ),
        (
            "stale-cwd",
            lambda s: check_context(s, "cwd"),
            {"label": "old", "delay": 0.4},
            2,
        ),
        (
            "stale-direnv-environment",
            lambda s: check_context(s, "env"),
            {"label": "old", "delay": 0.4},
            2,
        ),
        (
            "stale-width-keymap",
            lambda s: check_context(s, "width"),
            {"label": "old", "delay": 0.4},
            2,
        ),
        (
            "bounded-empty-enter-queue",
            check_bounded,
            {"label": "bounded", "delay": 0.5},
            2,
        ),
        (
            "failure-fallback",
            check_failure,
            {"label": "failure", "delay": 0.1, "mode": "fail"},
            2,
        ),
        ("timeout-fallback", check_failure, {"label": "timeout", "delay": 1.5}, 1),
        (
            "oversized-request-safe-fallback",
            check_oversized,
            {"label": "oversized", "delay": 0.05},
            2,
        ),
        ("restore-worker-cleanup", check_restore, {"label": "restore", "delay": 6}, 10),
        ("exit-worker-cleanup", check_exit, {"label": "exit", "delay": 6}, 10),
        (
            "continuation-prompt-preservation",
            check_continuation,
            {"label": "continuation", "delay": 0.4},
            2,
        ),
        (
            "bounded-worker-recovery",
            check_retry_limit,
            {"label": "retry-limit", "delay": 2},
            5,
        ),
        (
            "continuation-invalid-token-fallback",
            check_continuation_error,
            {"label": "continuation-error", "delay": 2},
            5,
        ),
        (
            "continuation-transport-fallback",
            lambda s: check_continuation_error(s, transport=True),
            {"label": "continuation-error", "delay": 2},
            5,
        ),
        (
            "yank-pop-after-async-redraw",
            check_yank_pop,
            {"label": "yank-chain", "delay": 0, "wait_for": "release-render"},
            10,
        ),
        (
            "kill-chain-after-async-redraw",
            check_kill_chain,
            {"label": "kill-chain", "delay": 0, "wait_for": "release-render"},
            10,
        ),
        (
            "kill-boundary-after-async-redraw",
            check_kill_boundary,
            {"label": "kill-boundary", "delay": 0, "wait_for": "release-render"},
            10,
        ),
    ]
    if args.case:
        cases = [case for case in cases if case[0] in args.case]
        if len(cases) != len(args.case):
            parser.error("unknown or duplicate case selection")
    if not cases:
        parser.error("no PTY cases selected")
    results = []
    for name, check, control, timeout in cases:
        session = None
        failure = None
        markers = []
        diagnostics = {}
        try:
            session = Session(
                args,
                adapter_bytes,
                control,
                timeout,
                name == "stale-direnv-environment",
                32768
                if name in ("large-exported-environment", "stale-direnv-environment")
                else 0,
                name == "oversized-request-safe-fallback",
                name
                in (
                    "yank-pop-after-async-redraw",
                    "kill-chain-after-async-redraw",
                    "kill-boundary-after-async-redraw",
                ),
            )
            check(session)
        except (AssertionError, OSError, RuntimeError, ValueError) as exc:
            failure = type(exc).__name__ + ": " + str(exc)
        finally:
            if session:
                markers = sorted({frame["kind"] for frame in session.frames})
                if failure:
                    diagnostics["synthetic_jobs"] = session.logs()[-8:]
                    diagnostics["last_state"] = {
                        key: session.frames[-1][key]
                        for key in (
                            "kind",
                            "seq",
                            "active",
                            "pending",
                            "enabled",
                            "restored",
                            "error",
                            "status",
                            "pipe",
                        )
                    }
                    diagnostics["visible_markers"] = re.findall(
                        r"AF-[A-Za-z0-9_-]+", session.frames[-1]["visible"]
                    )
                session.close()
                if not session.cleanup_ok:
                    failure = (
                        failure + "; " if failure else ""
                    ) + "owned process cleanup did not complete naturally"
        result = {
            "name": name,
            "passed": failure is None,
            "failure": failure,
            "markers": markers,
            "diagnostics": diagnostics,
        }
        results.append(result)
        print(json.dumps(result), flush=True)
        args.output.write_text(
            json.dumps(
                {
                    "passed": all(row["passed"] for row in results),
                    "adapter_sha256": adapter_sha256,
                    "standard_init_sha256": hashlib.sha256(
                        args.standard_init.encode()
                    ).hexdigest(),
                    "tty_contents_saved": False,
                    "user_environment_inherited": False,
                    "tests": results,
                },
                indent=2,
            )
            + "\n"
        )
        if name == "accepted-render-and-user-jobs" and failure:
            break
    return 0 if all(row["passed"] for row in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
