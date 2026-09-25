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
		up)
			[[ "$output" == *"task: [hermes:up]"* ]]
			[[ "$output" == *"-p personal-ops gateway status"* ]]
			;;
		restart)
			[[ "$output" == *"task: [hermes:restart]"* ]]
			[[ "$output" == *"-p personal-ops gateway status"* ]]
			;;
		down)
			[[ "$output" == *"hermes gateway stop"* ]]
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
			up)
				[[ "$output" == *"task: [hermes:up]"* ]]
				[[ "$output" == *"-p $profile gateway status"* ]]
				;;
			restart)
				[[ "$output" == *"task: [hermes:restart]"* ]]
				[[ "$output" == *"-p $profile gateway status"* ]]
				;;
			down)
				[[ "$output" == *"hermes gateway stop"* ]]
				;;
			esac
		done
	done
}

@test "legacy Docker-named stop task controls the native gateway without Docker" {
	run task --dir "$REPO_ROOT" --dry --force hermes:docker:down

	[ "$status" -eq 0 ]
	[[ "$output" == *"task: [hermes:down]"* ]]
	[[ "$output" == *"hermes gateway stop"* ]]
	[[ "$output" != *"docker compose"* ]]
}
