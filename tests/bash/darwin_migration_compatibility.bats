#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
	REAL_TASK="$(command -v task)"
	BIN="$BATS_TEST_TMPDIR/bin"
	COMMAND_LOG="$BATS_TEST_TMPDIR/commands.log"
	mkdir -p "$BIN"
	: >"$COMMAND_LOG"
	# The compatibility command must not execute any migration, verification,
	# package-management or privileged operation, even when old args are supplied.
	for command in bash brew nix sudo verify-darwin-package.sh verify-darwin-packages.sh migrate-darwin-provider.sh; do
		cat >"$BIN/$command" <<'EOF'
#!/bin/sh
printf '%s\n' "$0 $*" >>"$COMMAND_LOG"
exit 97
EOF
		chmod +x "$BIN/$command"
	done
	export PATH="$BIN:$PATH" COMMAND_LOG
	export DOTFILES_NIX_COMMAND="$BIN/nix"
	export DOTFILES_BREW_COMMAND="$BIN/brew"
	export DOTFILES_DARWIN_VERIFY_COMMAND="$BIN/verify-darwin-package.sh"
	export DOTFILES_DARWIN_VERIFICATION="$BIN/verify-darwin-packages.sh"
}

@test "darwin migrate remains a public listed compatibility command" {
	run "$REAL_TASK" --color=false --dir "$REPO_ROOT" --list
	[ "$status" -eq 0 ]
	[[ "$output" == *"darwin:migrate:"* ]]
	[[ "$output" == *"Deprecated"* ]]
	[ ! -s "$COMMAND_LOG" ]
}

@test "darwin migrate without arguments only explains retirement" {
	run "$REAL_TASK" --dir "$REPO_ROOT" darwin:migrate
	[ "$status" -eq 0 ]
	[[ "$output" == *"Automatic Darwin provider migration has been retired."* ]]
	[[ "$output" == *"No packages or data were changed."* ]]
	[ ! -s "$COMMAND_LOG" ]
}

@test "darwin migrate ignores legacy arguments without evaluating shell input" {
	run "$REAL_TASK" --dir "$REPO_ROOT" darwin:migrate -- \
		--id wezterm --store-path '/old path' --feature WithHermes \
		'; brew uninstall wezterm' '$(nix build)' '`sudo true`'
	[ "$status" -eq 0 ]
	[[ "$output" == *"Automatic Darwin provider migration has been retired."* ]]
	[[ "$output" == *"No packages or data were changed."* ]]
	[ ! -s "$COMMAND_LOG" ]
}
