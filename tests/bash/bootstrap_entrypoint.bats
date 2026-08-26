#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	TEST_HOME="$BATS_TEST_TMPDIR/home"
	STUB_BIN="$BATS_TEST_TMPDIR/bin"
	mkdir -p "$TEST_HOME" "$STUB_BIN"

	write_stub tmux 'exit 0'
	write_stub curl 'exit 0'
	write_stub git 'exit 0'
	write_stub tar 'exit 0'
	write_stub dpkg 'exit 0'
	write_stub apt-get 'exit 0'
	write_stub sudo 'exec "$@"'
	write_stub chezmoi 'echo "chezmoi stub"; exit 0'
	write_stub npm 'echo "npm stub"; exit 0'
	write_stub nvim 'if [ "${1:-}" = "--version" ]; then echo "NVIM v0.10.0"; exit 0; fi; exit 0'
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

@test "bootstrap.sh reaches completion without hanging when installers are stubbed" {
	export HOME="$TEST_HOME"
	export PATH="$STUB_BIN:$PATH"

	run timeout 30 bash "$REPO_ROOT/bootstrap.sh" 2>&1

	[ "$status" -eq 0 ]
	[[ "$output" == *"bootstrap complete"* ]]
}

@test "bootstrap.sh installs Codex without installing Claude Code" {
	export HOME="$TEST_HOME"
	export NPM_LOG="$BATS_TEST_TMPDIR/npm.log"
	write_stub npm '
printf "args=%s\n" "$*" >>"$NPM_LOG"
printf "prefix=%s\n" "${NPM_CONFIG_PREFIX:-}" >>"$NPM_LOG"
if [ "${1:-}" = "config" ]; then exit 70; fi
exit 0
'
	filtered_path=""
	IFS=: read -r -a path_entries <<<"$PATH"
	for path_entry in "${path_entries[@]}"; do
		[ -n "$path_entry" ] || continue
		{ [ -x "$path_entry/claude" ] || [ -x "$path_entry/codex" ]; } && continue
		if [ -z "$filtered_path" ]; then
			filtered_path="$path_entry"
		else
			filtered_path="$filtered_path:$path_entry"
		fi
	done
	export PATH="$STUB_BIN:$filtered_path"

	run timeout 30 bash "$REPO_ROOT/bootstrap.sh" 2>&1

	[ "$status" -eq 0 ]
	[[ "$output" == *"bootstrap complete"* ]]
	grep -q '@openai/codex' "$NPM_LOG"
	! grep -qi 'claude' "$NPM_LOG"
}

@test "chezmoi apply preserves the Codex npm path in future shells" {
	export HOME="$TEST_HOME"
	export MANAGED_SHELLS="$REPO_ROOT/chezmoi/shells"
	export PATH="$STUB_BIN:$PATH"
	write_stub npm '
mkdir -p "$NPM_CONFIG_PREFIX/bin"
printf "#!/usr/bin/env sh\nexit 0\n" >"$NPM_CONFIG_PREFIX/bin/codex"
chmod +x "$NPM_CONFIG_PREFIX/bin/codex"
'
	write_stub chezmoi '
cp "$MANAGED_SHELLS/profile" "$HOME/.profile"
cp "$MANAGED_SHELLS/bashrc" "$HOME/.bashrc"
'

	run timeout 30 bash "$REPO_ROOT/bootstrap.sh" 2>&1

	[ "$status" -eq 0 ]
	grep -q '\.local/npm/bin' "$HOME/.profile"
	grep -q '\.local/npm/bin' "$HOME/.bashrc"
}
