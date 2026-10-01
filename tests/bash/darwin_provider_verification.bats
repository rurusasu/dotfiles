#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
	WORKFLOW="$REPO_ROOT/scripts/sh/verify-darwin-packages.sh"
	REPORT="$BATS_TEST_TMPDIR/report"
	STORE="$BATS_TEST_TMPDIR/store"
	BIN="$BATS_TEST_TMPDIR/bin"
	COMMAND_LOG="$BATS_TEST_TMPDIR/commands.log"
	mkdir -p "$REPORT" "$BIN" "$STORE/bin" "$STORE/Applications/Test.app/Contents/MacOS"
	: >"$COMMAND_LOG"
	: >"$STORE/Applications/Test.app/Contents/Info.plist"
	write_stub app 'exit 0'
	cp "$BIN/app" "$STORE/Applications/Test.app/Contents/MacOS/Test"
	write_stub op 'printf "version\n" >>"$COMMAND_LOG"; exit "${VERSION_STATUS:-0}"'
	cp "$BIN/op" "$STORE/bin/op"
	cat >"$REPORT/support.json" <<'JSON'
{
  "_1password-cli": {"darwin":{"provider":"nix","identity":{"command":"op","versionArgs":["--version"]}},"installFeature":null},
  "app": {"darwin":{"provider":"nix","source":"custom","identity":{"appName":"Test.app","bundleId":"com.example.test","executable":"Test"}},"installFeature":null},
  "optional": {"darwin":{"provider":"nix","identity":{"command":"op","versionArgs":["--version"]}},"installFeature":"WithHermes"},
  "plain": {"darwin":{"provider":"nix","identity":"plain"},"installFeature":null},
  "cask": {"darwin":{"provider":"homebrew-cask","identity":"cask"},"installFeature":null}
}
JSON
	jq -n --arg store "$STORE" --arg absent "$BATS_TEST_TMPDIR/absent" '{"_1password-cli":$store,app:$store,optional:$absent,plain:$absent,cask:$absent}' >"$REPORT/darwin-paths.json"
	write_stub nix 'printf "nix %s\n" "$*" >>"$COMMAND_LOG"; printf "%s\n" "$REPORT"; exit "${BUILD_STATUS:-0}"'
	write_stub plistbuddy 'case "$2" in "Print :CFBundleIdentifier") printf "%s\n" "${BUNDLE_ID:-com.example.test}";; "Print :CFBundleExecutable") echo Test;; *) exit 2;; esac'
	write_stub codesign 'printf "codesign\n" >>"$COMMAND_LOG"'
	write_stub spctl 'printf "spctl\n" >>"$COMMAND_LOG"'
	export REPORT COMMAND_LOG
	export DOTFILES_NIX_COMMAND="$BIN/nix"
	export DOTFILES_PLISTBUDDY_COMMAND="$BIN/plistbuddy"
	export DOTFILES_CODESIGN_COMMAND="$BIN/codesign"
	export DOTFILES_SPCTL_COMMAND="$BIN/spctl"
	unset DOTFILES_DARWIN_VERIFY_COMMAND
}

write_stub() {
	printf '#!/usr/bin/env bash\nset -euo pipefail\n%s\n' "$2" >"$BIN/$1"
	chmod +x "$BIN/$1"
}

@test "current provider verification batches metadata and checks active app and command identities" {
	run /bin/bash "$WORKFLOW"
	[ "$status" -eq 0 ]
	[ "$(grep -c '^nix ' "$COMMAND_LOG")" -eq 1 ]
	grep -Fxq 'nix build .#package-support-report --no-link --print-out-paths' "$COMMAND_LOG"
	grep -Fxq version "$COMMAND_LOG"
	grep -Fxq codesign "$COMMAND_LOG"
	grep -Fxq spctl "$COMMAND_LOG"
}

@test "enabled feature verifies its current provider without requiring unrelated optional providers" {
	jq --arg store "$STORE" '.optional = $store' "$REPORT/darwin-paths.json" >"$REPORT/paths.tmp"
	mv "$REPORT/paths.tmp" "$REPORT/darwin-paths.json"
	run /bin/bash "$WORKFLOW" --feature WithHermes
	[ "$status" -eq 0 ]
	[ "$(grep -c '^version$' "$COMMAND_LOG")" -eq 2 ]
}

@test "missing enabled feature output fails while disabled feature paths are ignored" {
	run /bin/bash "$WORKFLOW" --feature WithHermes
	[ "$status" -ne 0 ]
	[[ "$output" == *"realized store path is unavailable"* ]]
}

@test "app identity mismatch fails before signature checks" {
	export BUNDLE_ID=com.example.wrong
	run /bin/bash "$WORKFLOW"
	[ "$status" -ne 0 ]
	[[ "$output" == *"CFBundleIdentifier mismatch for app"* ]]
	! grep -q '^codesign' "$COMMAND_LOG"
}

@test "command version failure propagates before later app verification" {
	export VERSION_STATUS=42
	run /bin/bash "$WORKFLOW"
	[ "$status" -eq 42 ]
	! grep -q '^codesign' "$COMMAND_LOG"
}

@test "malformed structured identity reaches the verifier and fails" {
	jq '.app.darwin.identity = {}' "$REPORT/support.json" >"$REPORT/support.tmp"
	mv "$REPORT/support.tmp" "$REPORT/support.json"
	run /bin/bash "$WORKFLOW"
	[ "$status" -ne 0 ]
	[[ "$output" == *"Darwin verification identity is missing for app"* ]]
}

@test "metadata build failure stops before provider verification" {
	export BUILD_STATUS=43
	run /bin/bash "$WORKFLOW"
	[ "$status" -eq 43 ]
	! grep -q '^version' "$COMMAND_LOG"
}

@test "unsafe catalog ID fails before invoking the package verifier" {
	jq '. + {"../escape": .app}' "$REPORT/support.json" >"$REPORT/support.tmp"
	mv "$REPORT/support.tmp" "$REPORT/support.json"
	run /bin/bash "$WORKFLOW"
	[ "$status" -ne 0 ]
	[[ "$output" == *"invalid catalog ID"* ]]
	! grep -q '^version' "$COMMAND_LOG"
}
