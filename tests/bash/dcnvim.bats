#!/usr/bin/env bats
# Unit tests for the shared POSIX dcnvim implementation.

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	HELPER="$REPO_ROOT/scripts/sh/dcnvim.sh"
	TEST_HOME="$BATS_TEST_TMPDIR/home"
	STUB_BIN="$BATS_TEST_TMPDIR/bin"
	DEVCONTAINER_LOG="$BATS_TEST_TMPDIR/devcontainer.log"
	DEVCONTAINER_PAYLOAD_LOG="$BATS_TEST_TMPDIR/devcontainer-payload.log"
	mkdir -p "$TEST_HOME" "$STUB_BIN"

	export HOME="$TEST_HOME"
	export PATH="$STUB_BIN:$PATH"
	export DEVCONTAINER_LOG
	export DEVCONTAINER_PAYLOAD_LOG

	# shellcheck source=/dev/null
	source "$HELPER"
}

write_stub() {
	local name="$1"
	local body="$2"
	cat >"$STUB_BIN/$name" <<EOF
#!/usr/bin/env bash
set -euo pipefail
$body
EOF
	chmod +x "$STUB_BIN/$name"
}

write_devcontainer_stub() {
	write_stub devcontainer '
{
  printf "argc=%s\n" "$#"
  for arg in "$@"; do
    printf "arg=%s\n" "$arg"
  done
} >> "$DEVCONTAINER_LOG"

case "${1:-}" in
  up)
    exit "${DEVCONTAINER_UP_STATUS:-0}"
    ;;
  exec)
    last_arg=""
    for arg in "$@"; do
      last_arg="$arg"
    done
    printf "%s\n" "$last_arg" > "$DEVCONTAINER_PAYLOAD_LOG"
    exit 0
    ;;
esac

exit 2
'
}

write_ghq_stub() {
	write_stub ghq '
case "${1:-}" in
  root)
    printf "%s\n" "$GHQ_ROOT"
    ;;
  list)
    printf "%s\n" "$GHQ_SELECTED"
    ;;
esac
'
}

write_fzf_stub() {
	write_stub fzf '
cat >/dev/null
if [ "${FZF_STATUS:-0}" -ne 0 ]; then
  exit "$FZF_STATUS"
fi
printf "%s\n" "$FZF_SELECTED"
'
}

@test "explicit workspace runs devcontainer up and exec with nvim tmux payload" {
	workspace="$BATS_TEST_TMPDIR/project"
	mkdir -p "$workspace/.devcontainer"
	write_devcontainer_stub

	run dcnvim "$workspace"

	[ "$status" -eq 0 ]
	log="$(cat "$DEVCONTAINER_LOG")"
	[[ "$log" == *"arg=up"* ]]
	[[ "$log" == *"arg=--workspace-folder"* ]]
	[[ "$log" == *"arg=$workspace"* ]]
	[[ "$log" == *"arg=--dotfiles-repository"* ]]
	[[ "$log" == *"arg=https://github.com/rurusasu/dotfiles"* ]]
	[[ "$log" == *"arg=--dotfiles-install-command"* ]]
	[[ "$log" == *"arg=bootstrap.sh"* ]]

	payload="$(cat "$DEVCONTAINER_PAYLOAD_LOG")"
	[[ "$payload" == *'export PATH="$HOME/.local/bin:$PATH"'* ]]
	[[ "$payload" == *"command -v nvim"* ]]
	[[ "$payload" == *"command -v tmux"* ]]
	[[ "$payload" == *"tmux new -A -s 'project' 'nvim .'"* ]]
}

@test "workspace picker uses ghq and fzf when cwd has no devcontainer" {
	cwd="$BATS_TEST_TMPDIR/cwd"
	ghq_root="$BATS_TEST_TMPDIR/ghq"
	workspace="$ghq_root/github.com/foo/bar"
	mkdir -p "$cwd" "$workspace/.devcontainer"
	cd "$cwd"

	export GHQ_ROOT="$ghq_root"
	export GHQ_SELECTED="github.com/foo/bar"
	export FZF_SELECTED="github.com/foo/bar"
	write_devcontainer_stub
	write_ghq_stub
	write_fzf_stub

	run dcnvim

	[ "$status" -eq 0 ]
	log="$(cat "$DEVCONTAINER_LOG")"
	[[ "$log" == *"arg=$workspace"* ]]
	payload="$(cat "$DEVCONTAINER_PAYLOAD_LOG")"
	[[ "$payload" == *"tmux new -A -s 'bar' 'nvim .'"* ]]
}

@test "custom dotfiles repository url is passed to devcontainer up" {
	workspace="$BATS_TEST_TMPDIR/project"
	mkdir -p "$workspace/.devcontainer"
	export DOTFILES_REPOSITORY_URL="https://example.invalid/dotfiles.git"
	write_devcontainer_stub

	run dcnvim "$workspace"

	[ "$status" -eq 0 ]
	log="$(cat "$DEVCONTAINER_LOG")"
	[[ "$log" == *"arg=https://example.invalid/dotfiles.git"* ]]
}

@test "missing devcontainer config fails before devcontainer up" {
	workspace="$BATS_TEST_TMPDIR/project"
	mkdir -p "$workspace"
	write_devcontainer_stub

	run dcnvim "$workspace"

	[ "$status" -eq 1 ]
	[[ "$output" == *"dcnvim: no .devcontainer/ or .devcontainer.json under $workspace"* ]]
	[ ! -f "$DEVCONTAINER_LOG" ]
}

@test "devcontainer up failure returns error before exec" {
	workspace="$BATS_TEST_TMPDIR/project"
	mkdir -p "$workspace/.devcontainer"
	export DEVCONTAINER_UP_STATUS=42
	write_devcontainer_stub

	run dcnvim "$workspace"

	[ "$status" -eq 1 ]
	[[ "$output" == *"dcnvim: devcontainer up failed"* ]]
	[ ! -f "$DEVCONTAINER_PAYLOAD_LOG" ]
}

@test "session name is shell quoted in container payload" {
	workspace="$BATS_TEST_TMPDIR/team's repo"
	mkdir -p "$workspace/.devcontainer"
	write_devcontainer_stub

	run dcnvim "$workspace"

	[ "$status" -eq 0 ]
	payload="$(cat "$DEVCONTAINER_PAYLOAD_LOG")"
	[[ "$payload" == *"tmux new -A -s 'team'\\''s repo' 'nvim .'"* ]]
}
