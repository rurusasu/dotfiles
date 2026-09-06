#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	command -v task >/dev/null 2>&1 || skip "go-task is unavailable"
}

assert_no_profile_gateway_lifecycle() {
	local plan="$1"

	[[ ! "$plan" =~ -p[[:space:]]+[^[:space:]]+[[:space:]]+gateway[[:space:]]+(start|run|stop|restart) ]]
}

@test "generic profile lifecycle uses the root multiplexer and profile status" {
	for action in up down restart; do
		run task --dir "$REPO_ROOT" --dry --force "hermes:profile:$action" PROFILE=personal-ops

		[ "$status" -eq 0 ]
		assert_no_profile_gateway_lifecycle "$output"
		case "$action" in
		up | restart)
			[[ "$output" == *"task: [hermes:bootstrap]"* ]]
			[[ "$output" == *"-p personal-ops gateway status"* ]]
			;;
		down)
			[[ "$output" == *"docker compose -f docker/hermes-service/compose.yml stop hermes"* ]]
			[[ "$output" != *"docker compose -f docker/hermes-service/compose.yml down"* ]]
			;;
		esac
	done
}

@test "named profile lifecycle aliases never dispatch named gateways" {
	for profile in rick hoffman risarisa nancy; do
		for action in up down restart; do
			run task --dir "$REPO_ROOT" --dry --force "hermes:$profile:$action"

			[ "$status" -eq 0 ]
			assert_no_profile_gateway_lifecycle "$output"
			case "$action" in
			up | restart)
				[[ "$output" == *"task: [hermes:bootstrap]"* ]]
				[[ "$output" == *"-p $profile gateway status"* ]]
				;;
			down)
				[[ "$output" == *"docker compose -f docker/hermes-service/compose.yml stop hermes"* ]]
				[[ "$output" != *"docker compose -f docker/hermes-service/compose.yml down"* ]]
				;;
			esac
		done
	done
}
