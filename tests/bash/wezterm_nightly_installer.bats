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
	SOURCE_APP="$TEST_ROOT/source/WezTerm.app"

	mkdir -p \
		"$SOURCE_APP/Contents/MacOS" \
		"$SOURCE_APP/Contents/Resources/shell-completion" \
		"$BIN_DIR" \
		"$TEST_ROOT/bin"
	touch \
		"$SOURCE_APP/Contents/MacOS/wezterm" \
		"$SOURCE_APP/Contents/MacOS/wezterm-gui" \
		"$SOURCE_APP/Contents/MacOS/wezterm-mux-server" \
		"$SOURCE_APP/Contents/MacOS/strip-ansi-escapes" \
		"$SOURCE_APP/Contents/Resources/shell-completion/bash" \
		"$SOURCE_APP/Contents/Resources/shell-completion/fish" \
		"$SOURCE_APP/Contents/Resources/shell-completion/zsh"
	cat >"$TEST_ROOT/bin/curl" <<'EOF'
#!/bin/sh
while [ "$#" -gt 0 ]; do
	if [ "$1" = "-o" ]; then
		touch "$2"
		shift 2
		continue
	fi
	shift
done
EOF
	cat >"$TEST_ROOT/bin/unzip" <<'EOF'
#!/bin/sh
source_app="$WEZTERM_TEST_SOURCE_APP"
destination=""
while [ "$#" -gt 0 ]; do
	if [ "$1" = "-d" ]; then
		destination="$2"
		shift 2
		continue
	fi
	shift
done
mkdir -p "$destination"
cp -R "$source_app" "$destination/WezTerm.app"
EOF
	chmod +x "$TEST_ROOT/bin/curl" "$TEST_ROOT/bin/unzip"
}

@test "installs the nightly app and command links when WezTerm is absent" {
	run env \
		PATH="$TEST_ROOT/bin:$PATH" \
		WEZTERM_TEST_SOURCE_APP="$SOURCE_APP" \
		WEZTERM_NIGHTLY_URL="https://example.invalid/WezTerm-macos-nightly.zip" \
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
		PATH="$TEST_ROOT/bin:$TEST_ROOT:$PATH" \
		WEZTERM_TEST_SOURCE_APP="$SOURCE_APP" \
		WEZTERM_NIGHTLY_URL="https://invalid.example/wezterm.zip" \
		WEZTERM_APP_PATH="$APP_PATH" \
		WEZTERM_BIN_DIR="$BIN_DIR" \
		WEZTERM_CURL_COMMAND=failing-curl \
		"$INSTALLER"
	[ "$status" -eq 0 ]
}
