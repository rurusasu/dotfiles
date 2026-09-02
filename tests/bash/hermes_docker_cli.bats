#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	TEST_HOME="$BATS_TEST_TMPDIR/home"
	STUB_BIN="$BATS_TEST_TMPDIR/bin"
	DOCKER_CAPTURE="$BATS_TEST_TMPDIR/docker.args"
	mkdir -p "$TEST_HOME/.dotfiles/docker/hermes-service" "$STUB_BIN"
	touch "$TEST_HOME/.dotfiles/docker/hermes-service/compose.yml"
	write_stub docker-compose '
printf "%s\n" "$*" >"$DOCKER_CAPTURE"
'
	export HOME="$TEST_HOME"
	export PATH="$STUB_BIN:/usr/bin:/bin"
	export DOCKER_CAPTURE
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

@test "Docker CLI uses the default dotfiles compose file and forwards arguments" {
	cd "$TEST_HOME"
	run "$REPO_ROOT/scripts/sh/hermes-docker.sh" -p personal-ops config check

	[ "$status" -eq 0 ]
	[ "$(<"$DOCKER_CAPTURE")" = "-f $TEST_HOME/.dotfiles/docker/hermes-service/compose.yml exec -T hermes /opt/hermes/bin/hermes -p personal-ops config check" ]
}

@test "Docker CLI honors an explicit compose file" {
	compose_file="$BATS_TEST_TMPDIR/custom-compose.yml"
	touch "$compose_file"

	run env HERMES_COMPOSE_FILE="$compose_file" "$REPO_ROOT/scripts/sh/hermes-docker.sh" --version

	[ "$status" -eq 0 ]
	[ "$(<"$DOCKER_CAPTURE")" = "-f $compose_file exec -T hermes /opt/hermes/bin/hermes --version" ]
}

@test "Docker CLI reports how to configure a missing compose file" {
	rm "$TEST_HOME/.dotfiles/docker/hermes-service/compose.yml"
	cd "$TEST_HOME"

	run "$REPO_ROOT/scripts/sh/hermes-docker.sh" --version

	[ "$status" -ne 0 ]
	[[ "$output" == *"HERMES_COMPOSE_FILE"* ]]
}
