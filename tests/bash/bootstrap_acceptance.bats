#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	FIXTURE_ROOT="$REPO_ROOT/.github/e2e"
	RUNNER="$FIXTURE_ROOT/run-bootstrap-acceptance.sh"
	RUNTIME_STARTER="$FIXTURE_ROOT/start-bootstrap-runtime.sh"
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

@test "NixOS VM E2E routes installers through the acceptance fixture" {
	workflow="$REPO_ROOT/.github/workflows/ci-nix.yml"
	nixos_test="$REPO_ROOT/nix/tests/build/bootstrap-nixos.nix"

	grep -Fq '.#checks.x86_64-linux.bootstrap-nixos-vm' "$workflow"
	grep -q '.github/e2e/run-bootstrap-acceptance.sh' "$nixos_test"
	[ "$(grep -c '.github/e2e/start-bootstrap-runtime.sh' "$nixos_test")" -eq 2 ]
	! grep -Eq 'DOTFILES_HERMES_(DASHBOARD_AUTH|AGENT_SLACK_1PASSWORD)_ENABLED' \
		"$workflow" "$nixos_test"
}

@test "acceptance runtime starts the complete stack on its external network" {
	stub_bin="$BATS_TEST_TMPDIR/bin"
	export COMMAND_LOG="$BATS_TEST_TMPDIR/commands.log"
	mkdir -p "$stub_bin"
	cat >"$stub_bin/docker" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$COMMAND_LOG"
if [[ $* == "network inspect local-ai-services" ]]; then
	exit "${NETWORK_EXISTS_STATUS:-1}"
fi
EOF
	chmod +x "$stub_bin/docker"

	run env PATH="$stub_bin:$PATH" "$RUNTIME_STARTER"

	[ "$status" -eq 0 ]
	grep -Fxq 'network inspect local-ai-services' "$COMMAND_LOG"
	grep -Fxq 'network create local-ai-services' "$COMMAND_LOG"
	grep -Fxq "compose -f $REPO_ROOT/docker/hermes-service/compose.yml up --detach --wait" "$COMMAND_LOG"

	: >"$COMMAND_LOG"
	run env PATH="$stub_bin:$PATH" NETWORK_EXISTS_STATUS=0 "$RUNTIME_STARTER"
	[ "$status" -eq 0 ]
	grep -Fxq 'network inspect local-ai-services' "$COMMAND_LOG"
	! grep -q 'network create local-ai-services' "$COMMAND_LOG"
	grep -Fq 'compose -f ' "$COMMAND_LOG"
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

@test "NixOS bootstrap VM provides task before Hermes bootstrap" {
	nixos_test="$REPO_ROOT/nix/tests/build/bootstrap-nixos.nix"

	grep -Eq '^[[:space:]]+go-task([[:space:]]|$)' "$nixos_test"
}

@test "acceptance runner installs only fixture plumbing before invoking install.sh" {
	test_root="$BATS_TEST_TMPDIR/repo"
	mkdir -p "$test_root/docker/hermes-service" "$test_root/docker/local-ai-services" "$test_root/activated/bin"
	cat >"$test_root/activated/bin/op" <<'EOF'
#!/usr/bin/env bash
exit 99
EOF
	chmod +x "$test_root/activated/bin/op"
	cat >"$test_root/activated/bin/docker" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
	chmod +x "$test_root/activated/bin/docker"
	cat >"$test_root/install.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
command -v op
export PATH="$DOTFILES_ACCEPTANCE_REPO_ROOT/activated/bin:$PATH"
. "$DOTFILES_ACCEPTANCE_REPO_ROOT/scripts/sh/install-common.sh"
. "$DOTFILES_ACCEPTANCE_REPO_ROOT/scripts/sh/hermes-sidecar-common.sh"
[[ $(dotfiles_hermes_op_command) == "$DOTFILES_ACCEPTANCE_FIXTURE_ROOT/bin/op" ]]
cmp "$DOTFILES_ACCEPTANCE_FIXTURE_ROOT/bootstrap-compose.yml" \
	"$DOTFILES_ACCEPTANCE_REPO_ROOT/docker/hermes-service/compose.yml"
test -f "$DOTFILES_ACCEPTANCE_REPO_ROOT/docker/hermes-service/acceptance-health.json"
test "$DOTFILES_HERMES_CURL_EXECUTABLE" = \
	"$DOTFILES_ACCEPTANCE_FIXTURE_ROOT/bin/curl"
EOF
	chmod +x "$test_root/install.sh"
	mkdir -p "$test_root/scripts/sh"
	cp "$REPO_ROOT/scripts/sh/install-common.sh" "$test_root/scripts/sh/install-common.sh"
	cp "$REPO_ROOT/scripts/sh/hermes-sidecar-common.sh" "$test_root/scripts/sh/hermes-sidecar-common.sh"

	run env \
		DOTFILES_ACCEPTANCE_REPO_ROOT="$test_root" \
		DOTFILES_ACCEPTANCE_FIXTURE_ROOT="$FIXTURE_ROOT" \
		PATH="$test_root/activated/bin:$PATH" \
		"$RUNNER"

	[ "$status" -eq 0 ]
	[[ "$output" == "$FIXTURE_ROOT/bin/op" ]]
}

@test "acceptance OP fixtures reject unapproved lookups" {
	op="$FIXTURE_ROOT/bin/op"

	run "$op" item get "GitHubUsedOpenClawPAT" \
		--account my.1password.com --vault openclaw --format json
	[ "$status" -eq 0 ]
	[[ "$output" == *'"id":"acceptance-GitHubUsedOpenClawPAT"'* ]]

	run "$op" item get "Google Calendar MCP" \
		--account my.1password.com --vault openclaw --format json
	[ "$status" -eq 0 ]
	[[ "$output" == *'"id":"acceptance-Google Calendar MCP"'* ]]
	[[ "$output" == *'"label":"oauth_credentials_json"'* ]]
	[[ "$output" == *'"label":"tokens_json"'* ]]
	printf '%s\n' "$output" | jq -e '
		.fields
		| map({key: .label, value: (.value | fromjson)})
		| from_entries
		| .oauth_credentials_json.installed.client_id == "acceptance-client-id"
		  and .tokens_json.accounts.shared.refresh_token == "acceptance-refresh-token"
	' >/dev/null

	run "$op" item get "Nancy" \
		--account my.1password.com --vault openclaw --format json
	[ "$status" -eq 0 ]
	[[ "$output" == *'"id":"acceptance-Nancy"'* ]]

	for profile in Kuroda Shiraishi; do
		run "$op" item get "$profile" \
			--account my.1password.com --vault openclaw --format json
		[ "$status" -eq 0 ]
		[[ "$output" == *"\"id\":\"acceptance-$profile\""* ]]
	done

	run "$op" signin --account my.1password.com
	[ "$status" -eq 0 ]
	[[ "$output" == 'acceptance-session' ]]

	run "$op" --account my.1password.com read \
		'op://openclaw/3bgd5qtytxuvuauauyqr2p4iki/credential'
	[ "$status" -eq 0 ]
	[ "$output" = 'acceptance-hermes-service-account-token' ]

	run "$op" item get "Hermes X API MCP" \
		--account my.1password.com --vault openclaw --format json
	[ "$status" -eq 0 ]
	[[ "$output" == *'"id":"acceptance-Hermes X API MCP"'* ]]
	[[ "$output" == *'"label":"X_API_CLIENT_ID"'* ]]
	[[ "$output" == *'"label":"X_API_CLIENT_SECRET"'* ]]
	[[ "$output" == *'"label":"X_API_REFRESH_TOKEN"'* ]]
	printf '%s\n' "$output" | jq -e '
		.fields
		| map(select(.label == "X_API_REFRESH_TOKEN"))
		| length == 1 and .[0].section.label == "Refresh Token"
	' >/dev/null

	run "$op" item get "Unapproved Item" \
		--account my.1password.com --vault openclaw --format json
	[ "$status" -ne 0 ]

	run "$op" item get "Google Calendar MCP" \
		--account my.1password.com --vault Private --format json
	[ "$status" -ne 0 ]
}

@test "acceptance compose serves health from nginx and BusyBox document roots" {
	compose="$FIXTURE_ROOT/bootstrap-compose.yml"

	[ "$(grep -Fc 'exec /bin/httpd -f -p 80 -h /www' "$compose")" -ge 1 ]
	[ "$(grep -Fc "exec nginx -g 'daemon off;'" "$compose")" -ge 1 ]
	grep -Fq 'xapi-mcp:' "$compose"
	grep -Fq '    working_dir: /' "$compose"
	grep -Fq 'browser-mcp:' "$compose"
	grep -Fq 'name: local-ai-services' "$compose"
	grep -Fq 'external: true' "$compose"
	grep -Fq './acceptance-health.json:/fixture/health:ro' "$compose"
	grep -Fq 'cp /fixture/health /www/health' "$compose"
	grep -Fq 'cp /fixture/health /www/api/health' "$compose"
	grep -Fq 'cp /fixture/health /usr/share/nginx/html/health' "$compose"
	grep -Fq 'cp /fixture/health /usr/share/nginx/html/api/health' "$compose"
	grep -Fq './xurl-fixture.sh:/node_modules/.bin/xurl:ro' "$compose"
	grep -Fq 'install -m 0755 "$FIXTURE_ROOT/xurl-fixture.sh"' "$RUNNER"
	test -x "$FIXTURE_ROOT/xurl-fixture.sh"

	run "$FIXTURE_ROOT/xurl-fixture.sh" token
	[ "$status" -eq 0 ]
	run "$FIXTURE_ROOT/xurl-fixture.sh" unsupported
	[ "$status" -ne 0 ]
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

@test "Hermes bootstrap CI keeps the feature Taskfile contract" {
	workflow="$REPO_ROOT/.github/workflows/ci-nix.yml"
	pre_commit="$REPO_ROOT/.pre-commit-config.yaml"

	grep -Fq 'uses: ./.github/actions/detect-ci-changes' "$workflow"
	grep -Fq 'needs.changes.outputs.nix' "$workflow"
	grep -Eq 'taskfiles/hermes/taskfile\\.yml' "$pre_commit"
}
