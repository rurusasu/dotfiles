#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	SUT="$REPO_ROOT/scripts/sh/hermes-gmail.sh"
	export HERMES_DATA_DIR="$BATS_TEST_TMPDIR/hermes-data"
	export HERMES_COMPOSE_FILE="$BATS_TEST_TMPDIR/compose.yml"
	export DOCKER_LOG="$BATS_TEST_TMPDIR/docker.log"
	export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
	mkdir -p "$BATS_TEST_TMPDIR/bin" "$HERMES_DATA_DIR/profiles/rick"
	: >"$HERMES_COMPOSE_FILE"

	cat >"$BATS_TEST_TMPDIR/bin/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$DOCKER_LOG"
if [[ ${SWAP_GMAIL_TOKEN_PARENT:-0} == 1 && $* == *'hermes mcp login gmail'* ]]; then
  mkdir -p "$GMAIL_TOKEN_OUTSIDE"
  rmdir "$HERMES_DATA_DIR/profiles/rick/mcp-tokens" 2>/dev/null || true
  ln -s "$GMAIL_TOKEN_OUTSIDE" "$HERMES_DATA_DIR/profiles/rick/mcp-tokens"
  : >"$GMAIL_TOKEN_OUTSIDE/gmail.json"
  chmod 600 "$GMAIL_TOKEN_OUTSIDE/gmail.json"
elif [[ ${CREATE_GMAIL_TOKEN:-0} == 1 && $* == *'hermes mcp login gmail'* ]]; then
  mkdir -p "$HERMES_DATA_DIR/profiles/rick/mcp-tokens"
  : >"$HERMES_DATA_DIR/profiles/rick/mcp-tokens/gmail.json"
  chmod 600 "$HERMES_DATA_DIR/profiles/rick/mcp-tokens/gmail.json"
fi
EOF
	chmod +x "$BATS_TEST_TMPDIR/bin/docker"
}

@test "auth rejects unsafe and unknown profiles before starting Docker" {
	run "$SUT" auth '../outside'
	[ "$status" -eq 64 ]
	[[ "$output" == *"Invalid Hermes profile"* ]]
	[ ! -s "$DOCKER_LOG" ]

	run "$SUT" auth missing
	[ "$status" -eq 66 ]
	[[ "$output" == *"Hermes profile is not installed"* ]]
	[ ! -s "$DOCKER_LOG" ]
}

@test "auth uses the named profile home without passing OAuth values and requires its token cache" {
	export CREATE_GMAIL_TOKEN=1
	export GMAIL_MCP_CLIENT_ID='client-id-marker'
	export GMAIL_MCP_CLIENT_SECRET='client-secret-marker'

	run "$SUT" auth rick
	[ "$status" -eq 0 ]

	command_line="$(<"$DOCKER_LOG")"
	profile_home="$(cd -P "$HERMES_DATA_DIR/profiles/rick" && pwd)"
	[[ "$command_line" == *"compose -f $HERMES_COMPOSE_FILE run --rm --no-deps --volume $profile_home/mcp-tokens:/opt/data/profiles/rick/mcp-tokens:rw -e HERMES_HOME=/opt/data/profiles/rick hermes hermes mcp login gmail"* ]]
	[[ "$command_line" != *"client-id-marker"* ]]
	[[ "$command_line" != *"client-secret-marker"* ]]
	[ "$(stat -f '%Lp' "$HERMES_DATA_DIR/profiles/rick/mcp-tokens/gmail.json" 2>/dev/null || stat -c '%a' "$HERMES_DATA_DIR/profiles/rick/mcp-tokens/gmail.json")" = 600 ]
}

@test "auth fails when login completes without a private Gmail token cache" {
  run "$SUT" auth rick
  [ "$status" -eq 1 ]
  [[ "$output" == *"Gmail OAuth token cache is missing or not private"* ]]
}

@test "auth rejects an mcp-tokens symlink before starting OAuth" {
  mkdir -p "$BATS_TEST_TMPDIR/outside"
  ln -s "$BATS_TEST_TMPDIR/outside" "$HERMES_DATA_DIR/profiles/rick/mcp-tokens"

  run "$SUT" auth rick
  [ "$status" -eq 1 ]
  [[ "$output" == *"Gmail token cache parent is invalid"* ]]
  [ ! -s "$DOCKER_LOG" ]
}

@test "auth rejects an mcp-tokens parent replaced by a symlink during OAuth" {
  export SWAP_GMAIL_TOKEN_PARENT=1
  export GMAIL_TOKEN_OUTSIDE="$BATS_TEST_TMPDIR/outside"

  run "$SUT" auth rick
  [ "$status" -eq 1 ]
  [[ "$output" == *"Gmail token cache parent is invalid"* ]]
  [ -s "$DOCKER_LOG" ]
}

@test "test requires a private token cache and invokes the profile-local Gmail MCP probe" {
	run "$SUT" test rick
	[ "$status" -eq 1 ]
	[[ "$output" == *"Gmail OAuth token cache is missing or not private"* ]]
	[ ! -s "$DOCKER_LOG" ]

	mkdir -p "$HERMES_DATA_DIR/profiles/rick/mcp-tokens"
	: >"$HERMES_DATA_DIR/profiles/rick/mcp-tokens/gmail.json"
	chmod 600 "$HERMES_DATA_DIR/profiles/rick/mcp-tokens/gmail.json"

	run "$SUT" test rick
	[ "$status" -eq 0 ]
	profile_home="$(cd -P "$HERMES_DATA_DIR/profiles/rick" && pwd)"
	[[ "$(<"$DOCKER_LOG")" == *"compose -f $HERMES_COMPOSE_FILE run --rm --no-deps -T --volume $profile_home/mcp-tokens:/opt/data/profiles/rick/mcp-tokens:rw -e HERMES_HOME=/opt/data/profiles/rick hermes hermes mcp test gmail"* ]]
}
