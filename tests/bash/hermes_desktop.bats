#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	TEST_HOME="$BATS_TEST_TMPDIR/home"
	STUB_BIN="$BATS_TEST_TMPDIR/bin"
	DESKTOP_CAPTURE="$BATS_TEST_TMPDIR/desktop.env"
	DESKTOP_ARGS="$BATS_TEST_TMPDIR/desktop.args"
	CURL_CAPTURE="$BATS_TEST_TMPDIR/curl.args"
	REAL_JQ="$(command -v jq)"
	mkdir -p "$TEST_HOME/Library/Application Support/Hermes" "$STUB_BIN"

	write_stub curl '
printf "%s\n" "$*" >"$CURL_CAPTURE"
'
	write_stub open '
: >"$DESKTOP_CAPTURE"
printf "%s\n" "$*" >"$DESKTOP_ARGS"
'
	write_stub jq 'exec "$REAL_JQ" "$@"'
	export HOME="$TEST_HOME"
	export HERMES_DATA_DIR="$TEST_HOME/.hermes"
	export PATH="$STUB_BIN:/usr/bin:/bin"
	export DESKTOP_CAPTURE DESKTOP_ARGS CURL_CAPTURE REAL_JQ
	printf '%s\n' '{"version":2,"primary":"docker","connections":[{"id":"docker","kind":"remote","url":"http://127.0.0.1:9119/","authMode":"oauth"}]}' >"$TEST_HOME/Library/Application Support/Hermes/connections.json"
}

write_stub() {
	local name="$1"
	local body="$2"
	{
		printf '#!/usr/bin/env bash\n'
		printf 'set -euo pipefail\n'
		printf '%s\n' "$body"
	} >"$STUB_BIN/$name"
	chmod +x "$STUB_BIN/$name"
}

@test "Docker gateway launcher starts with the saved Desktop remote connection" {
	run "$REPO_ROOT/scripts/sh/hermes-desktop-docker.sh" --profile default

	[ "$status" -eq 0 ]
	[ "$(<"$DESKTOP_ARGS")" = "/Applications/Hermes.app --args --profile default" ]
	! grep -Fq 'HERMES_DESKTOP_REMOTE_TOKEN' "$DESKTOP_ARGS"
	! grep -Fq 'hermes-bootstrap-v1_' "$DESKTOP_ARGS"
	! grep -Fq 'opaque' <<<"$output"
	grep -Fq '127.0.0.1:9119/api/health' "$CURL_CAPTURE"
}

@test "Docker gateway launcher rejects an unconfigured Desktop remote connection" {
	: >"$TEST_HOME/Library/Application Support/Hermes/connections.json"

	run "$REPO_ROOT/scripts/sh/hermes-desktop-docker.sh"

	[ "$status" -ne 0 ]
	[[ "$output" == *"Settings > Gateway"* ]]
	[ ! -e "$DESKTOP_CAPTURE" ]
}

@test "Docker gateway launcher rejects a non-primary or wrong-url remote connection" {
	printf '%s\n' '{"version":2,"primary":"local","connections":[{"id":"local","kind":"local"},{"id":"docker","kind":"remote","url":"http://127.0.0.1:8642","authMode":"oauth"}]}' >"$TEST_HOME/Library/Application Support/Hermes/connections.json"

	run "$REPO_ROOT/scripts/sh/hermes-desktop-docker.sh"

	[ "$status" -ne 0 ]
	[[ "$output" == *"primary remote connection"* ]]
	[ ! -e "$DESKTOP_CAPTURE" ]
}

@test "Docker gateway launcher rejects a malformed token-auth envelope" {
	printf '%s\n' '{"version":2,"primary":"docker","connections":[{"id":"docker","kind":"remote","url":"http://127.0.0.1:9119","authMode":"token","token":{}}]}' >"$TEST_HOME/Library/Application Support/Hermes/connections.json"

	run "$REPO_ROOT/scripts/sh/hermes-desktop-docker.sh"

	[ "$status" -ne 0 ]
	[[ "$output" == *"primary remote connection"* ]]
	[ ! -e "$DESKTOP_CAPTURE" ]
}

@test "Docker gateway launcher refuses to start Desktop when the gateway is unavailable" {
	write_stub curl 'printf "%s\n" "$*" >"$CURL_CAPTURE"; exit 22'

	run "$REPO_ROOT/scripts/sh/hermes-desktop-docker.sh"

	[ "$status" -ne 0 ]
	[[ "$output" == *"task hermes:up"* ]]
	[ ! -e "$DESKTOP_CAPTURE" ]
}
