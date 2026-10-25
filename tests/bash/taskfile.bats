#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	command -v task >/dev/null 2>&1 || skip "go-task is unavailable"
}

assert_no_profile_gateway_lifecycle() {
	local plan="$1"

	[[ ! "$plan" =~ -p[[:space:]]+[^[:space:]]+[[:space:]]+gateway[[:space:]]+(start|run|stop|restart) ]]
}

@test "Hermes down stops the Home Manager native gateway" {
	run task --dir "$REPO_ROOT" --dry --force hermes:down

	[ "$status" -eq 0 ]
	[[ "$output" == *"systemctl --user stop hermes-agent.service"* ||
		("$output" == *"org.nix-community.home.hermes-agent"* && "$output" == *'launchctl bootout "$target"'*) ]]
	assert_no_profile_gateway_lifecycle "$output"
}

@test "profile status inspects the selected profile without changing gateway lifecycle" {
	run task --dir "$REPO_ROOT" --dry --force hermes:profile:status PROFILE=personal-ops

	[ "$status" -eq 0 ]
	[[ "$output" == *"hermes -p personal-ops gateway status"* ]]
	[[ "$output" != *"systemctl"* && "$output" != *"launchctl"* ]]
	assert_no_profile_gateway_lifecycle "$output"
}
