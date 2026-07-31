#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	INSTALLER="$REPO_ROOT/scripts/sh/install-wezterm-nightly.sh"
	TEST_ROOT="$BATS_TEST_TMPDIR/wezterm"
	APP_PATH="$TEST_ROOT/Applications/WezTerm.app"
	BIN_DIR="$TEST_ROOT/bin"
	BASH_COMPLETION="$TEST_ROOT/bash/wezterm"
	FISH_COMPLETION="$TEST_ROOT/fish/wezterm.fish"
	ZSH_COMPLETION="$TEST_ROOT/zsh/_wezterm"
	ARCHIVE="$TEST_ROOT/WezTerm-macos-nightly.zip"

	mkdir -p \
		"$TEST_ROOT/archive/WezTerm.app/Contents/MacOS" \
		"$TEST_ROOT/archive/WezTerm.app/Contents/Resources/shell-completion" \
		"$BIN_DIR"
	touch \
		"$TEST_ROOT/archive/WezTerm.app/Contents/MacOS/wezterm" \
		"$TEST_ROOT/archive/WezTerm.app/Contents/MacOS/wezterm-gui" \
		"$TEST_ROOT/archive/WezTerm.app/Contents/MacOS/wezterm-mux-server" \
		"$TEST_ROOT/archive/WezTerm.app/Contents/MacOS/strip-ansi-escapes" \
		"$TEST_ROOT/archive/WezTerm.app/Contents/Resources/shell-completion/bash" \
		"$TEST_ROOT/archive/WezTerm.app/Contents/Resources/shell-completion/fish" \
		"$TEST_ROOT/archive/WezTerm.app/Contents/Resources/shell-completion/zsh"
	(
		cd "$TEST_ROOT/archive"
		zip -qr "$ARCHIVE" WezTerm.app
	)
}

@test "installs the nightly app and command links when WezTerm is absent" {
	run env \
		WEZTERM_NIGHTLY_URL="file://$ARCHIVE" \
		WEZTERM_APP_PATH="$APP_PATH" \
		WEZTERM_BIN_DIR="$BIN_DIR" \
		WEZTERM_BASH_COMPLETION_PATH="$BASH_COMPLETION" \
		WEZTERM_FISH_COMPLETION_PATH="$FISH_COMPLETION" \
		WEZTERM_ZSH_COMPLETION_PATH="$ZSH_COMPLETION" \
		"$INSTALLER"
	[ "$status" -eq 0 ]
	[ -d "$APP_PATH" ]
	[ "$(readlink "$BIN_DIR/wezterm")" = "$APP_PATH/Contents/MacOS/wezterm" ]
	[ "$(readlink "$BIN_DIR/wezterm-gui")" = "$APP_PATH/Contents/MacOS/wezterm-gui" ]
	[ "$(readlink "$BIN_DIR/wezterm-mux-server")" = "$APP_PATH/Contents/MacOS/wezterm-mux-server" ]
	[ "$(readlink "$BIN_DIR/strip-ansi-escapes")" = "$APP_PATH/Contents/MacOS/strip-ansi-escapes" ]
	[ "$(readlink "$BASH_COMPLETION")" = "$APP_PATH/Contents/Resources/shell-completion/bash" ]
	[ "$(readlink "$FISH_COMPLETION")" = "$APP_PATH/Contents/Resources/shell-completion/fish" ]
	[ "$(readlink "$ZSH_COMPLETION")" = "$APP_PATH/Contents/Resources/shell-completion/zsh" ]
}

@test "does not download again when the nightly app is already installed" {
	mkdir -p "$APP_PATH"
	cat >"$TEST_ROOT/failing-curl" <<'EOF'
#!/bin/sh
exit 99
EOF
	chmod +x "$TEST_ROOT/failing-curl"

	run env \
		PATH="$TEST_ROOT:$PATH" \
		WEZTERM_NIGHTLY_URL="https://invalid.example/wezterm.zip" \
		WEZTERM_APP_PATH="$APP_PATH" \
		WEZTERM_BIN_DIR="$BIN_DIR" \
		WEZTERM_CURL_COMMAND=failing-curl \
		"$INSTALLER"
	[ "$status" -eq 0 ]
}
