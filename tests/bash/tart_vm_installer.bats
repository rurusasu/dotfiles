#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	INSTALLER="$REPO_ROOT/scripts/sh/install-tart-vm.sh"
	SETS="$REPO_ROOT/nix/packages/sets.nix"
	DARWIN_CONFIG="$REPO_ROOT/nix/darwin/default.nix"
	TASKFILE="$REPO_ROOT/taskfiles/install/taskfile.yml"
	TEST_HOME="$BATS_TEST_TMPDIR/home"
	TART_HOME="$TEST_HOME/.tart"
	STUB_BIN="$BATS_TEST_TMPDIR/bin"
	COMMAND_LOG="$BATS_TEST_TMPDIR/commands.log"
	mkdir -p "$TEST_HOME" "$TART_HOME" "$STUB_BIN"
	: >"$COMMAND_LOG"
	export HOME TART_HOME COMMAND_LOG
}

write_tart_stub() {
	cat >"$STUB_BIN/tart" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'tart %s\n' "$*" >>"$COMMAND_LOG"
mkdir -p "$TART_HOME/vms/${3:-unknown}"
EOF
	chmod +x "$STUB_BIN/tart"
}

write_df_stub() {
	cat >"$STUB_BIN/df" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
printf '/dev/mock 100000000 0 36700160 0%% /\n'
EOF
	chmod +x "$STUB_BIN/df"
}

@test "catalog declares Tart as a macOS Homebrew formula" {
	run awk '
		/^    tart = \{/ { in_entry=1 }
		in_entry { print }
		in_entry && /^    };/ { exit }
	' "$SETS"

	[ "$status" -eq 0 ]
	[[ "$output" == *'provider = "homebrew-formula"'* ]]
	[[ "$output" == *'formula = "openai/tools/tart"'* ]]
}

@test "nix-darwin consumes catalog Homebrew formulas" {
	grep -q 'brews = sets.darwinBrews' "$DARWIN_CONFIG"
	grep -q 'darwinBrews' "$SETS"
}

@test "macOS install tasks expose an explicit Tart VM preparation step" {
	run awk '
		/^  tart:prepare:/ { in_task=1 }
		in_task { print }
		in_task && /^[^ ]/ { exit }
	' "$TASKFILE"

	[ "$status" -eq 0 ]
	[[ "$output" == *'scripts/sh/install-tart-vm.sh'* ]]
	[[ "$output" == *'platforms: [darwin]'* ]]
}

@test "Tart preparation skips an existing VM without invoking Tart" {
	write_tart_stub
	mkdir -p "$TART_HOME/vms/tahoe-base"

	run env DOTFILES_TART_COMMAND="$STUB_BIN/tart" DOTFILES_TART_MIN_FREE_GIB=999999 "$INSTALLER"

	[ "$status" -eq 0 ]
	[[ "$output" == *"already exists"* ]]
	[ ! -s "$COMMAND_LOG" ]
}

@test "Tart preparation rejects insufficient space before cloning" {
	write_tart_stub

	run env DOTFILES_TART_COMMAND="$STUB_BIN/tart" DOTFILES_TART_MIN_FREE_GIB=999999 "$INSTALLER"

	[ "$status" -ne 0 ]
	[[ "$output" == *"Insufficient free space"* ]]
	[ ! -s "$COMMAND_LOG" ]
}

@test "Tart preparation rejects a capacity threshold that would overflow" {
	write_tart_stub

	run env DOTFILES_TART_COMMAND="$STUB_BIN/tart" DOTFILES_TART_MIN_FREE_GIB=8796093022208 "$INSTALLER"

	[ "$status" -ne 0 ]
	[[ "$output" == *"DOTFILES_TART_MIN_FREE_GIB is too large"* ]]
	[ ! -s "$COMMAND_LOG" ]
}

@test "Tart preparation treats leading-zero capacity as decimal" {
	write_tart_stub
	write_df_stub

	run env PATH="$STUB_BIN:$PATH" \
		DOTFILES_TART_COMMAND="$STUB_BIN/tart" \
		DOTFILES_TART_MIN_FREE_GIB=040 \
		"$INSTALLER"

	[ "$status" -ne 0 ]
	[[ "$output" == *"Insufficient free space"* ]]
	[ ! -s "$COMMAND_LOG" ]
}

@test "Tart preparation accepts leading-zero capacity with digit eight" {
	write_tart_stub
	write_df_stub

	run env PATH="$STUB_BIN:$PATH" \
		DOTFILES_TART_COMMAND="$STUB_BIN/tart" \
		DOTFILES_TART_MIN_FREE_GIB=08 \
		DOTFILES_TART_VM_NAME=eight-gib \
		"$INSTALLER"

	[ "$status" -eq 0 ]
	grep -Fxq 'tart clone ghcr.io/cirruslabs/macos-tahoe-base:latest eight-gib' "$COMMAND_LOG"
}

@test "Tart preparation clones the configured image into TART_HOME" {
	write_tart_stub

	run env DOTFILES_TART_COMMAND="$STUB_BIN/tart" \
		DOTFILES_TART_MIN_FREE_GIB=0 \
		DOTFILES_TART_IMAGE=ghcr.io/example/macos:tag \
		DOTFILES_TART_VM_NAME=test-vm \
		"$INSTALLER"

	[ "$status" -eq 0 ]
	grep -Fxq 'tart clone ghcr.io/example/macos:tag test-vm' "$COMMAND_LOG"
	[ -d "$TART_HOME/vms/test-vm" ]
}

@test "Tart preparation rejects reserved VM directory names" {
	write_tart_stub

	run env DOTFILES_TART_COMMAND="$STUB_BIN/tart" \
		DOTFILES_TART_MIN_FREE_GIB=0 \
		DOTFILES_TART_VM_NAME=.. \
		"$INSTALLER"

	[ "$status" -ne 0 ]
	[[ "$output" == *"unsupported characters"* ]]
}
