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

@test "production Linux installers leave Docker Hermes bootstrap out of native setup" {
	for file in "$REPO_ROOT/install.sh" "$REPO_ROOT/scripts/sh/install-nixos.sh"; do
		! grep -Fq 'hermes:bootstrap' "$file"
		! grep -Fq 'docker/hermes-service/compose.yml' "$file"
		! grep -q -- '--runtime' "$file"
	done
	grep -Fq 'nixos-rebuild switch' "$REPO_ROOT/scripts/sh/install-nixos.sh"
	grep -Fq '{{.HERMES_COMPOSE_FILE}}' "$REPO_ROOT/taskfiles/hermes/taskfile.yml"
}

@test "CI devcontainer pins Nix for the unskipped POSIX suite" {
	config="$REPO_ROOT/.devcontainer/ci/devcontainer.json"
	lock="$REPO_ROOT/.devcontainer/ci/devcontainer-lock.json"
	workflow="$REPO_ROOT/.github/workflows/ci-other.yml"
	feature='ghcr.io/devcontainers/features/nix:1.3.1'

	jq -e --arg feature "$feature" '
		.features[$feature]
		| .version == "2.34.8"
		  and .multiUser == true
		  and .extraNixConfig == "experimental-features = nix-command flakes"
	' "$config" >/dev/null
	jq -e --arg feature "$feature" '
		.features[$feature]
		| .version == "1.3.1"
		  and (.resolved | startswith("ghcr.io/devcontainers/features/nix@sha256:"))
		  and (.integrity | startswith("sha256:"))
	' "$lock" >/dev/null
	[ "$(grep -c -- '--frozen-lockfile' "$workflow")" -eq 1 ]
}

@test "Hermes bootstrap CI uses runtime contracts without Python unit-test gates" {
	workflow="$REPO_ROOT/.github/workflows/ci-nix.yml"
	pre_commit="$REPO_ROOT/.pre-commit-config.yaml"
	taskfile="$REPO_ROOT/taskfiles/hermes/taskfile.yml"

	grep -Fq 'uses: ./.github/actions/detect-ci-changes' "$workflow"
	grep -Fq 'needs.changes.outputs.nix' "$workflow"
	grep -Fq 'Hermes Runtime Contracts' "$workflow"
	! grep -Eq 'python3? -m unittest|setup-python|hermes-bootstrap-tests' "$workflow"
	! grep -Eq 'hermes:bootstrap:test' "$pre_commit" "$taskfile"
}
