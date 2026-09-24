#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	command -v chezmoi >/dev/null 2>&1 || skip "chezmoi is required to render the pnpm installer"
	TEST_ROOT="$BATS_TEST_TMPDIR/pnpm-runtime"
	mkdir -p "$TEST_ROOT/stub-bin" "$TEST_ROOT/home"

cat >"$TEST_ROOT/stub-bin/pnpm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >>"$PNPM_COMMAND_LOG"

if [ "${1:-}" = "list" ] && [ "${2:-}" = "-g" ]; then
	printf '%s\n' "${PNPM_LIST_JSON:-[]}"
elif [ "${1:-}" = "config" ] && [ "${2:-}" = "get" ] && [ "${3:-}" = "global-bin-dir" ]; then
	printf '%s\n' "${PNPM_REPORTED_GLOBAL_BIN_DIR:-}"
elif [ "${1:-}" = "remove" ] && [ "${2:-}" = "-g" ]; then
	exit "${PNPM_REMOVE_STATUS:-0}"
elif [ "${1:-}" = "add" ] && [ "${2:-}" = "-g" ]; then
	printf '%s\n' "$PATH" >>"$PNPM_ADD_PATH_LOG"
	printf '%s\n' "${PNPM_CONFIG_GLOBAL_BIN_DIR:-}" >>"$PNPM_ADD_GLOBAL_BIN_LOG"
	exit "${PNPM_ADD_STATUS:-0}"
fi
EOF
cat >"$TEST_ROOT/stub-bin/node" <<'EOF'
#!/usr/bin/env bash
case "${PNPM_GLOBAL_PACKAGES_JSON:-}" in
	*"\"${PNPM_GLOBAL_PACKAGE:-}\""*) exit 0 ;;
	*) exit 1 ;;
esac
EOF
	chmod +x "$TEST_ROOT/stub-bin/pnpm" "$TEST_ROOT/stub-bin/node"

	chezmoi --config /dev/null --config-format toml --source "$REPO_ROOT/chezmoi" \
		--destination "$TEST_ROOT/home" \
		--cache "$TEST_ROOT/cache" \
		--persistent-state "$TEST_ROOT/state.boltdb" \
		--override-data '{"chezmoi":{"os":"linux"}}' \
		execute-template --file "$REPO_ROOT/chezmoi/.chezmoiscripts/run_onchange_install-pnpm-global.sh.tmpl" \
		>"$TEST_ROOT/install-pnpm-global.sh"
}

run_installer() {
	env HOME="$TEST_ROOT/home" \
		CHEZMOI_SOURCE_DIR="$REPO_ROOT/chezmoi" \
		PNPM_ADD_PATH_LOG="$TEST_ROOT/add-path.log" \
		PNPM_ADD_GLOBAL_BIN_LOG="$TEST_ROOT/add-global-bin.log" \
		PNPM_COMMAND_LOG="$TEST_ROOT/pnpm-command.log" \
		PATH="$TEST_ROOT/stub-bin:$PATH" \
		bash "$TEST_ROOT/install-pnpm-global.sh"
}

@test "pnpm global bin from PNPM_HOME is available to package installs" {
	export PNPM_HOME="$TEST_ROOT/pnpm-home"

	run run_installer
	[ "$status" -eq 0 ]
	[ -s "$TEST_ROOT/add-path.log" ]
	[ ! -d "$PNPM_HOME/bin" ]
	while IFS= read -r install_path; do
		case ":$install_path:" in
			*":$PNPM_HOME/bin:"*) ;;
			*) return 1 ;;
		esac
	done <"$TEST_ROOT/add-path.log"
}

@test "pnpm reported global-bin-dir is used when PNPM_HOME is unset" {
	unset PNPM_HOME
	export PNPM_REPORTED_GLOBAL_BIN_DIR="$TEST_ROOT/reported-global-bin"

	run run_installer
	[ "$status" -eq 0 ]
	[ -s "$TEST_ROOT/add-path.log" ]
	[ ! -d "$PNPM_REPORTED_GLOBAL_BIN_DIR" ]
	while IFS= read -r install_path; do
		case ":$install_path:" in
			*":$PNPM_REPORTED_GLOBAL_BIN_DIR:"*) ;;
			*) return 1 ;;
		esac
	done <"$TEST_ROOT/add-path.log"
}

@test "pnpm reported tilde global-bin-dir is expanded before PATH validation" {
	unset PNPM_HOME
	export PNPM_REPORTED_GLOBAL_BIN_DIR='~/.local/share/pnpm/bin'

	run run_installer
	[ "$status" -eq 0 ]
	[[ "$output" == *"pnpm global bin directory is available in PATH: $TEST_ROOT/home/.local/share/pnpm/bin"* ]]
	grep -Fxq "$TEST_ROOT/home/.local/share/pnpm/bin" "$TEST_ROOT/add-global-bin.log"
	grep -Fq "$TEST_ROOT/home/.local/share/pnpm/bin" "$TEST_ROOT/add-path.log"
}

@test "configured global-bin-dir takes precedence over PNPM_HOME" {
	export PNPM_HOME="$TEST_ROOT/pnpm-home"
	export PNPM_REPORTED_GLOBAL_BIN_DIR="$TEST_ROOT/configured-global-bin"

	run run_installer
	[ "$status" -eq 0 ]
	[ -s "$TEST_ROOT/add-path.log" ]
	while IFS= read -r install_path; do
		case ":$install_path:" in
			*":$PNPM_REPORTED_GLOBAL_BIN_DIR:"*) ;;
			*) return 1 ;;
		esac
	done <"$TEST_ROOT/add-path.log"
}

@test "configured global-bin-dir is explicitly passed to each pnpm add process" {
	export PNPM_REPORTED_GLOBAL_BIN_DIR="$TEST_ROOT/configured-global-bin"

	run run_installer
	[ "$status" -eq 0 ]
	[ -s "$TEST_ROOT/add-global-bin.log" ]
	while IFS= read -r install_global_bin; do
		[ "$install_global_bin" = "$PNPM_REPORTED_GLOBAL_BIN_DIR" ] || return 1
	done <"$TEST_ROOT/add-global-bin.log"
}

@test "pnpm package failures are summarized and return nonzero" {
	export PNPM_HOME="$TEST_ROOT/pnpm-home"
	export PNPM_ADD_STATUS=1

	run run_installer
	[ "$status" -ne 0 ]
	[[ "$output" =~ pnpm[[:space:]]グローバル:.*失敗 ]]
}

@test "installed dsh removal failure is fatal and prevents reinstall" {
	export PNPM_LIST_JSON='[{"dependencies":{"@deepseek-ai/dsh":{}}}]'
	export PNPM_REMOVE_STATUS=1

	run run_installer
	[ "$status" -ne 0 ]
	[[ "$output" == *"@deepseek-ai/dsh の既存インストール削除に失敗しました"* ]]
	[[ "$output" =~ pnpm[[:space:]]グローバル:.*失敗 ]]
	grep -Fxq 'remove -g @deepseek-ai/dsh' "$TEST_ROOT/pnpm-command.log"
	! grep -E '^add -g .*@deepseek-ai/dsh$' "$TEST_ROOT/pnpm-command.log"
}
