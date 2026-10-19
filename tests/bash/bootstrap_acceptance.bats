#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "shared Bash runner executes every suite and clears installer overrides" {
	local stub_bin="$BATS_TEST_TMPDIR/bin"
	export CONTRACT_COMMAND_LOG="$BATS_TEST_TMPDIR/commands"
	mkdir -p "$stub_bin"
	cat >"$stub_bin/bats" <<'EOF'
#!/usr/bin/env bash
[[ ! -v DOTFILES_SKIP_FLAKE_UPDATE && ! -v DOTFILES_USER && ! -v DOTFILES_HOME && ! -v SUDO_USER ]] || exit 9
printf '%s\n' "$@" >"$CONTRACT_COMMAND_LOG"
EOF
	chmod +x "$stub_bin/bats"
	cd "$BATS_TEST_TMPDIR"
	run env PATH="$stub_bin:$PATH" DOTFILES_SKIP_FLAKE_UPDATE=1 DOTFILES_USER=runner DOTFILES_HOME=/tmp/runner SUDO_USER=runner \
		bash "$REPO_ROOT/scripts/sh/run-bash-tests.sh"
	[ "$status" -eq 0 ]
	[ "$(head -1 "$CONTRACT_COMMAND_LOG")" = --print-output-on-failure ]
	local suite expected_count=1
	for suite in "$REPO_ROOT"/tests/bash/*.bats; do
		grep -Fxq "tests/bash/${suite##*/}" "$CONTRACT_COMMAND_LOG"
		expected_count=$((expected_count + 1))
	done
	[ "$(wc -l <"$CONTRACT_COMMAND_LOG" | tr -d ' ')" -eq "$expected_count" ]
}

@test "shared Bash runner propagates a failed suite" {
	local stub_bin="$BATS_TEST_TMPDIR/bin"
	mkdir -p "$stub_bin"
	printf '#!/usr/bin/env bash\nexit 23\n' >"$stub_bin/bats"
	chmod +x "$stub_bin/bats"
	run env PATH="$stub_bin:$PATH" bash "$REPO_ROOT/scripts/sh/run-bash-tests.sh"
	[ "$status" -eq 23 ]
}

@test "shared Bash runner rejects an empty suite directory" {
	local fixture="$BATS_TEST_TMPDIR/empty-repo"
	mkdir -p "$fixture/scripts/sh" "$fixture/tests/bash"
	cp "$REPO_ROOT/scripts/sh/run-bash-tests.sh" "$fixture/scripts/sh/"
	run bash "$fixture/scripts/sh/run-bash-tests.sh"
	[ "$status" -eq 1 ]
	[[ "$output" == *'No Bash test suites found'* ]]
}
