#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	export HOME="$BATS_TEST_TMPDIR/home"
}

@test "does not expose a separate Google Calendar MCP HTTP service" {
	compose_file="$REPO_ROOT/docker/hermes-service/compose.yml"

	run grep -F "calendar-mcp:" "$compose_file"
	[ "$status" -eq 1 ]

	run grep -F '127.0.0.1:3500-3505:3500-3505' "$compose_file"
	[ "$status" -eq 0 ]
}

@test "pins the stdio Google Calendar MCP in the Hermes image" {
	run grep -F "ARG GOOGLE_CALENDAR_MCP_VERSION=2.6.2" \
		"$REPO_ROOT/docker/hermes-agent/Dockerfile"

	[ "$status" -eq 0 ]

	run grep -F '"@cocal/google-calendar-mcp@${GOOGLE_CALENDAR_MCP_VERSION}"' \
		"$REPO_ROOT/docker/hermes-agent/Dockerfile"

	[ "$status" -eq 0 ]
}
