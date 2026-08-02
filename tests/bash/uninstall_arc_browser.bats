#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	BREW_LOG="$BATS_TEST_TMPDIR/brew.log"
	FAKE_BREW="$BATS_TEST_TMPDIR/brew"
}

write_fake_brew() {
	local list_status="$1"
	printf '%s\n' \
		'#!/usr/bin/env bash' \
		'printf "%s\\n" "$*" >> "$BREW_LOG"' \
		"if [[ \"\$1 \" == \"list \" ]]; then exit $list_status; fi" \
		'exit 0' >"$FAKE_BREW"
	chmod +x "$FAKE_BREW"
}

@test "zaps an installed Arc cask" {
	write_fake_brew 0
	mkdir -p "$BATS_TEST_TMPDIR/home/Library/Caches/CloudKit/company.thebrowser.Browser"

	run env HOME="$BATS_TEST_TMPDIR/home" BREW_COMMAND="$FAKE_BREW" BREW_LOG="$BREW_LOG" \
		"$REPO_ROOT/scripts/sh/uninstall-arc-browser.sh"

	[ "$status" -eq 0 ]
	grep -Fxq 'list --cask --versions arc' "$BREW_LOG"
	grep -Fxq 'uninstall --cask --zap arc' "$BREW_LOG"
	[ ! -e "$BATS_TEST_TMPDIR/home/Library/Caches/CloudKit/company.thebrowser.Browser" ]
}

@test "does nothing when Arc is not installed" {
	write_fake_brew 1

	run env BREW_COMMAND="$FAKE_BREW" BREW_LOG="$BREW_LOG" \
		"$REPO_ROOT/scripts/sh/uninstall-arc-browser.sh"

	[ "$status" -eq 0 ]
	grep -Fxq 'list --cask --versions arc' "$BREW_LOG"
	! grep -Fq 'uninstall --cask --zap arc' "$BREW_LOG"
}
