#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	SUT="$REPO_ROOT/scripts/sh/hermes-gmail.sh"
	export HERMES_DATA_DIR="$BATS_TEST_TMPDIR/hermes-data"
	export COMMAND_LOG="$BATS_TEST_TMPDIR/commands.log"
	export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
	mkdir -p "$BATS_TEST_TMPDIR/bin" "$HERMES_DATA_DIR/google-gmail-mcp"
	printf '%s' '{"installed":{"client_id":"id","client_secret":"secret"}}' \
		>"$HERMES_DATA_DIR/google-gmail-mcp/gcp-oauth.keys.json"
	chmod 600 "$HERMES_DATA_DIR/google-gmail-mcp/gcp-oauth.keys.json"

	cat >"$BATS_TEST_TMPDIR/bin/npx" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'npx %s\n' "$*" >>"$COMMAND_LOG"
printf '%s' '{"tokens":{"refresh_token":"refresh"},"scopes":["gmail.readonly","gmail.compose"]}' >"$GMAIL_CREDENTIALS_PATH"
EOF
	chmod +x "$BATS_TEST_TMPDIR/bin/npx"
}

@test "auth uses one shared host OAuth flow" {
	run "$SUT" auth
	[ "$status" -eq 0 ]
	[[ "$(<"$COMMAND_LOG")" == *"npx --yes @artymclabin/gmail-mcp@1.2.3 auth --scopes=gmail.readonly,gmail.compose"* ]]
	[ "$(stat -c '%a' "$HERMES_DATA_DIR/google-gmail-mcp/credentials.json" 2>/dev/null || stat -f '%Lp' "$HERMES_DATA_DIR/google-gmail-mcp/credentials.json")" = 600 ]
}

@test "auth requires the shared private OAuth client before invoking npx" {
	chmod 644 "$HERMES_DATA_DIR/google-gmail-mcp/gcp-oauth.keys.json"
	run "$SUT" auth
	[ "$status" -eq 1 ]
	[[ "$output" == *"Shared Gmail OAuth client is missing or not private"* ]]
	[ ! -s "$COMMAND_LOG" ]
}
