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

run_install_provider_boundary() {
	# Keep the real profile resolution, post-activation ordering and both
	# verifiers. Replace unrelated host mutations at their function boundaries.
	run /bin/bash -c '
		source "$1/scripts/sh/install-macos.sh"
		shift
		preserve_shell_rc_for_nix_darwin() { :; }
		repair_homebrew_cask_link_directories() { :; }
		migrate_unmanaged_wezterm_install() { :; }
		apply_darwin_system() { :; }
		retire_tart_cli_profile() { :; }
		dotfiles_install_codex_npm() { :; }
		ensure_homebrew_cask_link_directories() { :; }
		dotfiles_install_herdr() { :; }
		apply_chezmoi() { printf "chezmoi\n" >>"$COMMAND_LOG"; }
		dotfiles_run_task() { printf "task %s\n" "$*" >>"$COMMAND_LOG"; }
		setup_ollama_runtime() { printf "ollama-start\n" >>"$COMMAND_LOG"; }
		setup_docker_runtime() { printf "docker-start\n" >>"$COMMAND_LOG"; }
		resolve_install_profile "$@"
		printf "profile %s %s %s\n" "$DOTFILES_WITH_OLLAMA" "$DOTFILES_WITH_DOCKER" "$DOTFILES_WITH_HERMES" >>"$COMMAND_LOG"
		finish_macos_install
	' bash "$REPO_ROOT" "$@"
}

prepare_install_provider_boundary() {
	# An installed Hermes provider exists; the implied Ollama provider does not.
	export HOME="$BATS_TEST_TMPDIR/home" USER=test-user SUDO_USER=test-user
	mkdir -p "$HOME"
	jq '. + {ollama: {darwin: {provider: "nix", identity: {command: "ollama", versionArgs: ["--version"]}}, installFeature: "WithOllama"}}' "$REPORT/support.json" >"$REPORT/support.tmp"
	mv "$REPORT/support.tmp" "$REPORT/support.json"
	jq --arg store "$STORE" --arg absent "$BATS_TEST_TMPDIR/absent-ollama" '.optional = $store | .ollama = $absent' "$REPORT/darwin-paths.json" >"$REPORT/paths.tmp"
	mv "$REPORT/paths.tmp" "$REPORT/darwin-paths.json"
	write_stub verify-environment 'printf "environment\n" >>"$COMMAND_LOG"'
	export DOTFILES_VERIFY_ENVIRONMENT="$BIN/verify-environment"
	export DOTFILES_DARWIN_VERIFICATION="$WORKFLOW"
	export DOTFILES_WITH_OLLAMA=0 DOTFILES_WITH_DOCKER=0 DOTFILES_WITH_HERMES=0
}

@test "Hermes-only install verifies implied Ollama before chezmoi and Hermes Desktop" {
	prepare_install_provider_boundary
	run_install_provider_boundary --with-hermes
	[ "$status" -ne 0 ]
	[[ "$output" == *"realized store path is unavailable"* ]]
	[[ "$output" == *"absent-ollama"* ]]
	grep -Fxq 'profile 0 0 1' "$COMMAND_LOG"
	! grep -qE '^(chezmoi|task |ollama-start|docker-start|environment)' "$COMMAND_LOG"
}

@test "default install ignores missing disabled optional providers" {
	prepare_install_provider_boundary
	run_install_provider_boundary
	[ "$status" -eq 0 ]
	grep -Fxq 'profile 0 0 0' "$COMMAND_LOG"
	grep -Fxq chezmoi "$COMMAND_LOG"
	grep -Fxq environment "$COMMAND_LOG"
	! grep -qE '^(task |ollama-start|docker-start)' "$COMMAND_LOG"
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
