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
  printf "op_token=%s\n" "${OP_SERVICE_ACCOUNT_TOKEN:-}"
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

@test "explicit workspace runs plain devcontainer up then bootstraps before nvim tmux payload" {
	workspace="$BATS_TEST_TMPDIR/project"
	mkdir -p "$workspace/.devcontainer"
	expected_workspace="$(_dcnvim_abs_path "$workspace")"
	write_devcontainer_stub

	run dcnvim "$workspace"

	[ "$status" -eq 0 ]
	log="$(cat "$DEVCONTAINER_LOG")"
	[[ "$log" == *"arg=up"* ]]
	[[ "$log" == *"arg=--workspace-folder"* ]]
	[[ "$log" == *"arg=$expected_workspace"* ]]
	[[ "$log" != *"arg=--dotfiles-repository"* ]]
	[[ "$log" != *"arg=--dotfiles-install-command"* ]]

	payload="$(cat "$DEVCONTAINER_PAYLOAD_LOG")"
	[[ "$payload" == *'export PATH="$HOME/.local/bin:$PATH"'* ]]
	[[ "$payload" == *"dotfiles_url='https://github.com/rurusasu/dotfiles'"* ]]
	[[ "$payload" == *"dotfiles_ref=''"* ]]
	[[ "$payload" == *'dotfiles_dir="$HOME/.dotfiles"'* ]]
	[[ "$payload" != *'HOME/dotfiles'* ]]
	[[ "$payload" == *"dotfiles_needs_bootstrap=0"* ]]
	[[ "$payload" == *'if [ -L "$dotfiles_dir" ] || [ ! -d "$dotfiles_dir/.git" ]; then'* ]]
	[[ "$payload" == *'git clone --depth=1 "$dotfiles_url" "$dotfiles_dir"'* ]]
	[[ "$payload" == *'current_url="$(git -C "$dotfiles_dir" config --get remote.origin.url || true)"'* ]]
	[[ "$payload" == *'if [ "$current_url" != "$dotfiles_url" ]; then'* ]]
	[[ "$payload" == *'if git -C "$dotfiles_dir" fetch --depth=1 origin; then'* ]]
	[[ "$payload" == *'if git -C "$dotfiles_dir" pull --ff-only --depth=1; then'* ]]
	[[ "$payload" == *"dcnvim: warning: failed to update dotfiles repository; using existing checkout"* ]]
	[[ "$payload" == *'if [ "$dotfiles_needs_bootstrap" -eq 1 ] || ! command -v nvim >/dev/null 2>&1 || ! command -v tmux >/dev/null 2>&1; then'* ]]
	[[ "$payload" == *'"$dotfiles_dir/bootstrap.sh"'* ]]
	[[ "$payload" == *"command -v nvim"* ]]
	[[ "$payload" == *"command -v tmux"* ]]
	[[ "$payload" == *"tmux new -A -s 'project' 'nvim .'"* ]]
}

@test "explicit workspace loads OP service account token before devcontainer up" {
	workspace="$BATS_TEST_TMPDIR/project"
	mkdir -p "$workspace/.devcontainer" "$HOME/.config/shell"
cat >"$HOME/.config/shell/secret.sh" <<'EOF'
[ "${DOTFILES_FORCE_SECRET_LOAD:-}" = "1" ] || return 99
[ "${DOTFILES_SECRET_LOAD_ONLY:-}" = "OP_SERVICE_ACCOUNT_TOKEN" ] || return 98
export OP_SERVICE_ACCOUNT_TOKEN="loaded-by-secret-loader"
EOF
	write_devcontainer_stub

	run dcnvim "$workspace"

	[ "$status" -eq 0 ]
	log="$(cat "$DEVCONTAINER_LOG")"
	[[ "$log" == *"op_token=loaded-by-secret-loader"* ]]
	[ -z "${DOTFILES_FORCE_SECRET_LOAD:-}" ]
	[ -z "${DOTFILES_SECRET_LOAD_ONLY:-}" ]
}

@test "workspace picker uses ghq and fzf when cwd has no devcontainer" {
	cwd="$BATS_TEST_TMPDIR/cwd"
	ghq_root="$BATS_TEST_TMPDIR/ghq"
	workspace="$ghq_root/github.com/foo/bar"
	mkdir -p "$cwd" "$workspace/.devcontainer"
	expected_workspace="$(_dcnvim_abs_path "$workspace")"
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
	[[ "$log" == *"arg=$expected_workspace"* ]]
	payload="$(cat "$DEVCONTAINER_PAYLOAD_LOG")"
	[[ "$payload" == *"tmux new -A -s 'bar' 'nvim .'"* ]]
}

@test "custom dotfiles repository url is used by bootstrap payload" {
	workspace="$BATS_TEST_TMPDIR/project"
	mkdir -p "$workspace/.devcontainer"
	export DOTFILES_REPOSITORY_URL="https://example.invalid/dotfiles.git"
	write_devcontainer_stub

	run dcnvim "$workspace"

	[ "$status" -eq 0 ]
	log="$(cat "$DEVCONTAINER_LOG")"
	[[ "$log" != *"arg=https://example.invalid/dotfiles.git"* ]]
	payload="$(cat "$DEVCONTAINER_PAYLOAD_LOG")"
	[[ "$payload" == *"dotfiles_url='https://example.invalid/dotfiles.git'"* ]]
}

@test "custom dotfiles repository ref is checked out by bootstrap payload" {
	workspace="$BATS_TEST_TMPDIR/project"
	mkdir -p "$workspace/.devcontainer"
	export DOTFILES_REPOSITORY_REF="feature/test-ref"
	write_devcontainer_stub

	run dcnvim "$workspace"

	[ "$status" -eq 0 ]
	payload="$(cat "$DEVCONTAINER_PAYLOAD_LOG")"
	[[ "$payload" == *"dotfiles_ref='feature/test-ref'"* ]]
	[[ "$payload" == *'if git -C "$dotfiles_dir" fetch --depth=1 origin "$dotfiles_ref" &&'* ]]
	[[ "$payload" == *'git -C "$dotfiles_dir" checkout --force FETCH_HEAD'* ]]
	[[ "$payload" == *"dcnvim: warning: failed to fetch dotfiles ref; using existing checkout"* ]]
}

@test "dotfiles update failures are best effort when checkout already exists" {
	workspace="$BATS_TEST_TMPDIR/project"
	mkdir -p "$workspace/.devcontainer"
	write_devcontainer_stub

	run dcnvim "$workspace"

	[ "$status" -eq 0 ]
	payload="$(cat "$DEVCONTAINER_PAYLOAD_LOG")"
	[[ "$payload" == *'if git -C "$dotfiles_dir" fetch --depth=1 origin; then'* ]]
	[[ "$payload" == *"dcnvim: warning: failed to update dotfiles repository; using existing checkout"* ]]
	[[ "$payload" == *'if [ "$dotfiles_needs_bootstrap" -eq 1 ] || ! command -v nvim >/dev/null 2>&1 || ! command -v tmux >/dev/null 2>&1; then'* ]]
	[[ "$payload" == *"tmux new -A -s 'project' 'nvim .'"* ]]
}

@test "missing devcontainer config fails before devcontainer up" {
	workspace="$BATS_TEST_TMPDIR/project"
	mkdir -p "$workspace"
	expected_workspace="$(_dcnvim_abs_path "$workspace")"
	write_devcontainer_stub

	run dcnvim "$workspace"

	[ "$status" -eq 1 ]
	[[ "$output" == *"dcnvim: no .devcontainer/ or .devcontainer.json under $expected_workspace"* ]]
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
