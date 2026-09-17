#!/usr/bin/env bats

setup() {
	export DISPLAY_HELPER="$BATS_TEST_DIRNAME/../../scripts/sh/install-display.sh"
}

@test "plain display preserves stdin and shell function state" {
	run bash -euc '
    source "$DISPLAY_HELPER"
    dotfiles_display_init
    change_state() { read -r answer; printf "input=%s\n" "$answer"; changed=yes; }
    dotfiles_step "Example phase" "Explain the operation." change_state <<< response
    test "$changed" = yes
  '
	[ "$status" -eq 0 ]
	[[ "$output" == *"[RUNNING] Example phase"* ]]
	[[ "$output" == *"input=response"* ]]
	[[ "$output" == *"[DONE] Example phase"* ]]
	[[ "$output" != *$'\033'* ]]
}

@test "failure preserves status and stops before later commands inside a function" {
	run bash -euc '
    source "$DISPLAY_HELPER"
    dotfiles_display_init
    fail() { bash -c "exit 37"; echo UNREACHABLE; }
    dotfiles_step "Fetching sources" "Download current sources." fail
    echo UNREACHABLE
  '
	[ "$status" -eq 37 ]
	[[ "$output" == *"[FAILED] Fetching sources (exit 37)"* ]]
	[[ "$output" != *UNREACHABLE* ]]
	[[ "$output" != *"[DONE]"* ]]
}

@test "successful steps clear failure context" {
	run bash -euc '
    source "$DISPLAY_HELPER"
    dotfiles_display_init
    dotfiles_step "Completed phase" "An operation." true
    exit 23
  '
	[ "$status" -eq 23 ]
	[[ "$output" != *"[FAILED] Completed phase"* ]]
}

@test "a caller without errexit still receives the command failure" {
	run bash -uc '
    source "$DISPLAY_HELPER"
    dotfiles_display_init
    dotfiles_step "Failed command" "An operation." bash -c "exit 37"
    exit "$?"
  '
	[ "$status" -eq 37 ]
	[[ "$output" != *"[DONE]"* ]]
	[[ "$output" == *"[FAILED] Failed command (exit 37)"* ]]
}

@test "terminal display keeps command descriptors interactive and resets styling" {
	run python3 - <<'PY'
import errno
import os
import pty

for no_color, term, command_status in [(False, 'xterm-256color', 0), (True, 'xterm-256color', 0), (False, 'dumb', 0), (False, 'xterm-256color', 37)]:
    pid, fd = pty.fork()
    if pid == 0:
        os.environ['TERM'] = term
        os.environ.pop('NO_COLOR', None)
        if no_color:
            os.environ['NO_COLOR'] = ''
        os.environ['COMMAND_STATUS'] = str(command_status)
        os.execlp('bash', 'bash', '-euc', '''
            source "$DISPLAY_HELPER"
            DOTFILES_LOG_PREFIX=test-display
            source "${DISPLAY_HELPER%/*}/install-common.sh"
            dotfiles_display_init
            dotfiles_log plain-marker 2>/dev/null
            interactive() { test -t 0; test -t 1; test -t 2; printf 'progress 1\rprogress 2\n'; return "$COMMAND_STATUS"; }
            dotfiles_step "Terminal phase" "Native output." interactive
        ''')
    output = b''
    while True:
        try:
            chunk = os.read(fd, 4096)
        except OSError as error:
            if error.errno != errno.EIO:
                raise
            break
        if not chunk:
            break
        output += chunk
    os.close(fd)
    _, status = os.waitpid(pid, 0)
    assert os.WEXITSTATUS(status) == command_status, output
    assert b'progress 1\rprogress 2' in output, output
    assert b'[test-display] plain-marker' in output, output
    if no_color or term == 'dumb':
        assert b'\x1b' not in output, output
    else:
        assert b'\x1b[1m[RUNNING]' in output, output
        assert b'\x1b[2m' in output, output
        if command_status:
            assert b'[FAILED] Terminal phase (exit 37)\x1b[0m' in output, output
            assert b'[DONE]' not in output, output
        else:
            assert output.endswith(b'\x1b[0m'), output
PY
	[ "$status" -eq 0 ]
}
