#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	FIXTURE_ROOT="$REPO_ROOT/.github/e2e"
	RUNNER="$FIXTURE_ROOT/run-bootstrap-acceptance.sh"
}

@test "destructive Linux E2E routes installers through the acceptance fixture" {
	workflow="$REPO_ROOT/.github/workflows/ci-bootstrap-e2e-linux.yml"
	nixos_test="$REPO_ROOT/nix/tests/bootstrap-nixos.nix"

	[ "$(grep -c '.github/e2e/run-bootstrap-acceptance.sh' "$workflow")" -ge 3 ]
	grep -q '.github/e2e/run-bootstrap-acceptance.sh' "$nixos_test"
	! grep -Eq 'DOTFILES_HERMES_(DASHBOARD_AUTH|AGENT_SLACK_1PASSWORD)_ENABLED' \
		"$workflow" "$nixos_test"
}

@test "production Linux installers keep the canonical Hermes Compose path" {
	for installer in install-linux.sh install-nixos.sh; do
		file="$REPO_ROOT/scripts/sh/$installer"
		grep -Fq 'COMPOSE_FILE="$DOTFILES_ROOT/docker/hermes-agent/compose.yml"' "$file"
		grep -Fq 'dotfiles_hermes_start_stack docker_command "$DOTFILES_ROOT/docker/hermes-agent/compose.yml"' "$file"
		! grep -q 'DOTFILES_COMPOSE_FILE' "$file"
	done
}

@test "acceptance runner installs only fixture plumbing before invoking install.sh" {
	test_root="$BATS_TEST_TMPDIR/repo"
	mkdir -p "$test_root/docker/hermes-agent" "$test_root/activated/bin"
	cat >"$test_root/activated/bin/op" <<'EOF'
#!/usr/bin/env bash
exit 99
EOF
	chmod +x "$test_root/activated/bin/op"
	cat >"$test_root/install.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
command -v op
export PATH="$DOTFILES_ACCEPTANCE_REPO_ROOT/activated/bin:$PATH"
. "$DOTFILES_ACCEPTANCE_REPO_ROOT/scripts/sh/install-common.sh"
. "$DOTFILES_ACCEPTANCE_REPO_ROOT/scripts/sh/hermes-agent.sh"
[[ $(dotfiles_hermes_op_command) == "$DOTFILES_ACCEPTANCE_FIXTURE_ROOT/bin/op" ]]
cmp "$DOTFILES_ACCEPTANCE_FIXTURE_ROOT/bootstrap-compose.yml" \
	"$DOTFILES_ACCEPTANCE_REPO_ROOT/docker/hermes-agent/compose.yml"
test -x "$DOTFILES_ACCEPTANCE_REPO_ROOT/docker/hermes-agent/hermes-bootstrap-fixture.sh"
cmp "$DOTFILES_ACCEPTANCE_FIXTURE_ROOT/hindsight-health.json" \
	"$DOTFILES_ACCEPTANCE_REPO_ROOT/docker/hermes-agent/hindsight-health.json"
test -x "$DOTFILES_ACCEPTANCE_REAL_CURL"
EOF
	chmod +x "$test_root/install.sh"
	mkdir -p "$test_root/scripts/sh"
	cp "$REPO_ROOT/scripts/sh/install-common.sh" "$test_root/scripts/sh/install-common.sh"
	cp "$REPO_ROOT/scripts/sh/hermes-agent.sh" "$test_root/scripts/sh/hermes-agent.sh"
	cp "$REPO_ROOT/scripts/sh/hermes-hindsight.sh" "$test_root/scripts/sh/hermes-hindsight.sh"

	run env \
		DOTFILES_ACCEPTANCE_REPO_ROOT="$test_root" \
		DOTFILES_ACCEPTANCE_FIXTURE_ROOT="$FIXTURE_ROOT" \
		"$RUNNER"

	[ "$status" -eq 0 ]
	[[ "$output" == "$FIXTURE_ROOT/bin/op" ]]
}

@test "acceptance secret fixtures are deterministic and reject unapproved lookups" {
	bootstrap="$FIXTURE_ROOT/hermes-bootstrap-fixture.sh"
	op="$FIXTURE_ROOT/bin/op"

	run bash -c ". '$REPO_ROOT/scripts/sh/hermes-agent.sh'; '$bootstrap' secret-plan | dotfiles_hermes_validate_secret_plan >/dev/null"
	[ "$status" -eq 0 ]

	run "$op" item get "GitHubUsedOpenClawPAT" \
		--account my.1password.com --vault openclaw --format json
	[ "$status" -eq 0 ]
	[[ "$output" == *'"id":"acceptance-GitHubUsedOpenClawPAT"'* ]]

	run "$op" item get "Google Calendar MCP" \
		--account my.1password.com --vault Private --format json
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

	run "$op" item get "Unapproved Item" \
		--account my.1password.com --vault openclaw --format json
	[ "$status" -ne 0 ]

	run "$op" item get "Google Calendar MCP" \
		--account my.1password.com --vault openclaw --format json
	[ "$status" -ne 0 ]
}

@test "acceptance compose serves health from nginx and BusyBox document roots" {
	compose="$FIXTURE_ROOT/bootstrap-compose.yml"

	grep -Fq 'exec /bin/httpd -f -p 80 -h /www' "$compose"
	grep -Fq "exec nginx -g 'daemon off;'" "$compose"
	grep -Fq 'xapi-mcp:' "$compose"
	grep -Fq './hermes-bootstrap-fixture.sh:/usr/share/nginx/html/health:ro' "$compose"
	grep -Fq './hermes-bootstrap-fixture.sh:/www/health:ro' "$compose"
}

@test "offline acceptance exercises Hindsight with deterministic Ollama fixtures" {
	compose="$FIXTURE_ROOT/bootstrap-compose.yml"
	ollama="$FIXTURE_ROOT/bin/ollama"
	curl="$FIXTURE_ROOT/bin/curl"

	grep -Fq 'hindsight:' "$compose"
	grep -Fq '127.0.0.1:8888:80' "$compose"
	grep -Fq './hindsight-health.json:/usr/share/nginx/html/health:ro' "$compose"
	test -x "$ollama"
	test -x "$curl"

	run "$ollama" pull qwen3.6:35b
	[ "$status" -eq 0 ]
	run "$ollama" pull qwen3-embedding:0.6b
	[ "$status" -eq 0 ]
	run "$ollama" pull unsupported-model
	[ "$status" -ne 0 ]

	run env DOTFILES_ACCEPTANCE_REAL_CURL=/usr/bin/false \
		"$curl" --fail --silent http://127.0.0.1:11434/api/tags
	[ "$status" -eq 0 ]
	printf '%s\n' "$output" | jq -e '
		.models | map(.name) == ["qwen3.6:35b", "qwen3-embedding:0.6b"]
	' >/dev/null
}

@test "Hermes bootstrap gates include the gh wrapper security suite" {
	wrapper='docker/hermes-agent/bootstrap/tests/test_gh_wrapper.sh'

	grep -Fq "$wrapper" "$REPO_ROOT/Taskfile.yml"
	grep -Fq "$wrapper" "$REPO_ROOT/.github/workflows/ci-hermes-bootstrap.yml"
}
