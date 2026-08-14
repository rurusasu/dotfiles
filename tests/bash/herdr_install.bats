#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	COMMON_INSTALLER="$REPO_ROOT/scripts/sh/install-common.sh"
	STUB_BIN="$BATS_TEST_TMPDIR/bin"
	COMMAND_LOG="$BATS_TEST_TMPDIR/commands.log"
	mkdir -p "$STUB_BIN"
	: >"$COMMAND_LOG"
	export PATH="$STUB_BIN:/usr/bin:/bin"
	export COMMAND_LOG STUB_BIN

	write_stub uname '
case "${1:-}" in
	-s) printf "%s\\n" "${HERDR_TEST_OS:-Linux}" ;;
	*) exit 2 ;;
esac
'
	write_stub brew '
printf "brew %s\\n" "$*" >>"$COMMAND_LOG"
if [[ ${1:-} == list ]]; then
	exit 1
fi
exit 0
'
	write_stub curl '
printf "curl %s\\n" "$*" >>"$COMMAND_LOG"
exit 0
'
	write_stub sh '
printf "sh %s\\n" "$*" >>"$COMMAND_LOG"
exit 0
'
	write_stub herdr '
printf "herdr %s\\n" "$*" >>"$COMMAND_LOG"
[[ ${1:-} == --version ]] && printf "herdr 0.8.0\\n"
exit 0
'
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

@test "macOS installs Herdr with Homebrew and verifies it" {
	export HERDR_TEST_OS=Darwin
	run bash -c 'source "$1"; dotfiles_install_herdr' _ "$COMMON_INSTALLER"
	[ "$status" -eq 0 ]
	grep -Fxq "brew install herdr" "$COMMAND_LOG"
	grep -Fxq "herdr --version" "$COMMAND_LOG"
}

@test "Linux installs Herdr with the official installer and verifies it" {
	export HERDR_TEST_OS=Linux
	run bash -c 'source "$1"; dotfiles_install_herdr' _ "$COMMON_INSTALLER"
	[ "$status" -eq 0 ]
	grep -Fxq "curl -fsSL https://herdr.dev/install.sh" "$COMMAND_LOG"
	grep -Fxq "sh " "$COMMAND_LOG"
	grep -Fxq "herdr --version" "$COMMAND_LOG"
}

@test "Herdr installation can be explicitly skipped" {
	export DOTFILES_SKIP_HERDR_INSTALL=1
	run bash -c 'source "$1"; dotfiles_install_herdr' _ "$COMMON_INSTALLER"
	[ "$status" -eq 0 ]
	[ ! -s "$COMMAND_LOG" ]
}
