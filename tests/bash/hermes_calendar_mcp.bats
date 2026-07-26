#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	export DOCKER_CONFIG="$HOME/.docker"
	export HOME="$BATS_TEST_TMPDIR/home"
}

@test "does not expose a separate Google Calendar MCP HTTP service" {
	run docker compose \
		-f "$REPO_ROOT/docker/hermes-agent/compose.yml" \
		config \
		--format json

	[ "$status" -eq 0 ]
	compose_json="$output"
	[ "$(jq -r '.services | has("calendar-mcp")' <<<"$compose_json")" = "false" ]
	[ "$(jq -r '.services.hermes.depends_on | has("calendar-mcp")' <<<"$compose_json")" = "false" ]
	[ "$(jq -r '.services.hermes.ports[] | select(.target == 3500) | .host_ip' <<<"$compose_json")" = "127.0.0.1" ]
}

@test "pins the stdio Google Calendar MCP in the Hermes image" {
	run docker build \
		-f "$REPO_ROOT/docker/hermes-agent/Dockerfile" \
		--check \
		"$REPO_ROOT/docker/hermes-agent"

	[ "$status" -eq 0 ]

	run grep -F "ARG GOOGLE_CALENDAR_MCP_VERSION=2.6.2" \
		"$REPO_ROOT/docker/hermes-agent/Dockerfile"

	[ "$status" -eq 0 ]

	run grep -F '"@cocal/google-calendar-mcp@${GOOGLE_CALENDAR_MCP_VERSION}"' \
		"$REPO_ROOT/docker/hermes-agent/Dockerfile"

	[ "$status" -eq 0 ]
}
