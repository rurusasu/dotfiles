#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	SUT="$REPO_ROOT/scripts/sh/hermes-gmail.sh"
	export HERMES_DATA_DIR="$BATS_TEST_TMPDIR/hermes-data"
	export HERMES_COMPOSE_FILE="$BATS_TEST_TMPDIR/compose.yml"
	export COMMAND_LOG="$BATS_TEST_TMPDIR/commands.log"
	export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
	mkdir -p "$BATS_TEST_TMPDIR/bin" "$HERMES_DATA_DIR/profiles/rick" \
		"$HERMES_DATA_DIR/google-gmail-mcp"
	: >"$HERMES_COMPOSE_FILE"
	printf '%s' '{"installed":{"client_id":"id","client_secret":"secret"}}' \
		>"$HERMES_DATA_DIR/google-gmail-mcp/gcp-oauth.keys.json"
	chmod 600 "$HERMES_DATA_DIR/google-gmail-mcp/gcp-oauth.keys.json"

	cat >"$BATS_TEST_TMPDIR/bin/docker" <<'EOF'
#!/usr/bin/env bash
printf 'docker %s\n' "$*" >>"$COMMAND_LOG"
EOF
	cat >"$BATS_TEST_TMPDIR/bin/npx" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'npx %s\n' "$*" >>"$COMMAND_LOG"
printf '%s' '{"tokens":{"refresh_token":"refresh"},"scopes":["gmail.readonly","gmail.compose"]}' >"$GMAIL_CREDENTIALS_PATH"
EOF
	chmod +x "$BATS_TEST_TMPDIR/bin/docker" "$BATS_TEST_TMPDIR/bin/npx"
}

@test "auth uses one shared host OAuth flow" {
	run "$SUT" auth
	[ "$status" -eq 0 ]
	[[ "$(<"$COMMAND_LOG")" == *"npx --yes @artymclabin/gmail-mcp@1.2.3 auth --scopes=gmail.readonly,gmail.compose"* ]]
	[ "$(stat -c '%a' "$HERMES_DATA_DIR/google-gmail-mcp/credentials.json" 2>/dev/null || stat -f '%Lp' "$HERMES_DATA_DIR/google-gmail-mcp/credentials.json")" = 600 ]
}

@test "rejects the removed profile-specific Gmail test action" {
	run "$SUT" test rick
	[ "$status" -eq 64 ]
	[ ! -s "$COMMAND_LOG" ]
}

@test "auth requires the shared private OAuth client before invoking npx" {
	chmod 644 "$HERMES_DATA_DIR/google-gmail-mcp/gcp-oauth.keys.json"
	run "$SUT" auth
	[ "$status" -eq 1 ]
	[[ "$output" == *"Shared Gmail OAuth client is missing or not private"* ]]
	[ ! -s "$COMMAND_LOG" ]
}

@test "auth does not invoke the Docker backend" {
	run "$SUT" auth
	[ "$status" -eq 0 ]
	[[ "$(<"$COMMAND_LOG")" != *docker* ]]
	[[ "$(<"$COMMAND_LOG")" == *"npx --yes @artymclabin/gmail-mcp@1.2.3 auth --scopes=gmail.readonly,gmail.compose"* ]]
}
