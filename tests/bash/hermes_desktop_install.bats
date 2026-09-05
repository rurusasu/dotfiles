#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	INSTALLER="$REPO_ROOT/scripts/sh/hermes-desktop-install.sh"
	TEST_HOME="$BATS_TEST_TMPDIR/home"
	STUB_BIN="$BATS_TEST_TMPDIR/bin"
	COMMAND_LOG="$BATS_TEST_TMPDIR/commands.log"
	export HOME="$TEST_HOME"
	export PATH="$STUB_BIN:/usr/bin:/bin"
	export COMMAND_LOG
	export DOTFILES_HERMES_APP_PATH="$BATS_TEST_TMPDIR/Applications/Hermes.app"
	export DOTFILES_HERMES_CLI_PATH="$TEST_HOME/.local/bin/hermes"
	export DOTFILES_HERMES_ROOT="$TEST_HOME/.hermes/hermes-agent"
	export DOTFILES_HERMES_OPEN_COMMAND="$STUB_BIN/open"
	export DOTFILES_HERMES_SETUP_WAIT_ATTEMPTS=2
	export DOTFILES_WAIT_SLEEP_SECONDS=0

	mkdir -p "$DOTFILES_HERMES_APP_PATH/Contents/MacOS" "$STUB_BIN"
	printf '#!/usr/bin/env bash\nexit 0\n' >"$DOTFILES_HERMES_APP_PATH/Contents/MacOS/Hermes-Setup"
	chmod +x "$DOTFILES_HERMES_APP_PATH/Contents/MacOS/Hermes-Setup"
	: >"$COMMAND_LOG"
}

write_stub() {
	local name="$1"
	local body="$2"
	{
		printf '#!/usr/bin/env bash\n'
		printf 'set -euo pipefail\n'
		printf '%s\n' "$body"
	} >"$STUB_BIN/$name"
	chmod +x "$STUB_BIN/$name"
}

write_completed_install() {
	local desktop="$DOTFILES_HERMES_ROOT/apps/desktop/release/mac-arm64/Hermes.app/Contents/MacOS/Hermes"
	mkdir -p "$(dirname "$DOTFILES_HERMES_CLI_PATH")" "$(dirname "$desktop")"
	touch "$DOTFILES_HERMES_ROOT/.hermes-bootstrap-complete"
	printf '#!/usr/bin/env bash\nprintf "Hermes 0.21.0\\n"\n' >"$DOTFILES_HERMES_CLI_PATH"
	printf '#!/usr/bin/env bash\nexit 0\n' >"$desktop"
	chmod +x "$DOTFILES_HERMES_CLI_PATH" "$desktop"
}

@test "official setup is launched without inherited Git command config" {
	write_stub open '
env | grep -Eq "^GIT_CONFIG_(COUNT|KEY_[0-9]+|VALUE_[0-9]+)=" && exit 41
printf "%s\n" "$PATH" | tr ":" "\n" | grep -Fx "$(dirname "$DOTFILES_HERMES_CLI_PATH")" >/dev/null || exit 42
printf "open %s\n" "$*" >>"$COMMAND_LOG"
desktop="$DOTFILES_HERMES_ROOT/apps/desktop/release/mac-arm64/Hermes.app/Contents/MacOS/Hermes"
mkdir -p "$(dirname "$DOTFILES_HERMES_CLI_PATH")" "$(dirname "$desktop")"
touch "$DOTFILES_HERMES_ROOT/.hermes-bootstrap-complete"
printf "#!/usr/bin/env bash\nprintf \\"Hermes 0.21.0\\\\n\\"\n" >"$DOTFILES_HERMES_CLI_PATH"
printf "#!/usr/bin/env bash\nexit 0\n" >"$desktop"
chmod +x "$DOTFILES_HERMES_CLI_PATH" "$desktop"
'

	run env \
		GIT_CONFIG_COUNT=2 \
		GIT_CONFIG_KEY_0=credential.helper \
		GIT_CONFIG_VALUE_0=one \
		GIT_CONFIG_KEY_1=url.example.insteadOf \
		GIT_CONFIG_VALUE_1=two \
		"$INSTALLER"

	[ "$status" -eq 0 ]
	grep -Fqx "open -n $DOTFILES_HERMES_APP_PATH" "$COMMAND_LOG"
}

@test "completed official install is an idempotent no-op" {
	write_completed_install
	write_stub open 'printf "open %s\n" "$*" >>"$COMMAND_LOG"; exit 42'

	run "$INSTALLER"

	[ "$status" -eq 0 ]
	[ ! -s "$COMMAND_LOG" ]
}

@test "a corrupt CLI causes the official setup to repair the install" {
	write_completed_install
	printf '#!/usr/bin/env bash\nexit 17\n' >"$DOTFILES_HERMES_CLI_PATH"
	chmod +x "$DOTFILES_HERMES_CLI_PATH"
	write_stub open '
printf "open %s\n" "$*" >>"$COMMAND_LOG"
printf "#!/usr/bin/env bash\nprintf \\"Hermes 0.21.0\\\\n\\"\n" >"$DOTFILES_HERMES_CLI_PATH"
chmod +x "$DOTFILES_HERMES_CLI_PATH"
'

	run "$INSTALLER"

	[ "$status" -eq 0 ]
	grep -Fqx "open -n $DOTFILES_HERMES_APP_PATH" "$COMMAND_LOG"
}

@test "setup does not succeed without the packaged Desktop artifact" {
	write_stub open '
mkdir -p "$(dirname "$DOTFILES_HERMES_CLI_PATH")" "$DOTFILES_HERMES_ROOT"
touch "$DOTFILES_HERMES_ROOT/.hermes-bootstrap-complete"
printf "#!/usr/bin/env bash\nprintf \\"Hermes 0.21.0\\\\n\\"\n" >"$DOTFILES_HERMES_CLI_PATH"
chmod +x "$DOTFILES_HERMES_CLI_PATH"
'

	run "$INSTALLER"

	[ "$status" -ne 0 ]
	[[ "$output" == *"Timed out waiting for Hermes Desktop setup completion"* ]]
}
