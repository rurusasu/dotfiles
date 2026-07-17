#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	VERIFIER="$REPO_ROOT/scripts/sh/verify-environment.sh"
	STUB_BIN="$BATS_TEST_TMPDIR/bin"
	COMMAND_LOG="$BATS_TEST_TMPDIR/commands.log"
	mkdir -p "$STUB_BIN"
	: >"$COMMAND_LOG"

	export PATH="$STUB_BIN:/usr/bin:/bin"
	export COMMAND_LOG
	export DOTFILES_COMPOSE_FILE="$REPO_ROOT/docker/hermes-agent/compose.yml"
	export DOTFILES_VERIFY_PLATFORM=darwin

	for command_name in \
		nix brew darwin-rebuild git gh chezmoi rg fd jq nvim node python3 go rustup docker; do
		write_stub "$command_name"
	done
}

write_stub() {
	local command_name="$1"
	cat >"$STUB_BIN/$command_name" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
command_name="${0##*/}"
printf '%s %s\n' "$command_name" "$*" >>"$COMMAND_LOG"
if [[ $command_name == "chezmoi" && ${1:-} == "verify" && -n ${CHEZMOI_VERIFY_FAIL:-} ]]; then
	exit 1
fi
if [[ $command_name == "docker" ]]; then
	case "$*" in
		*" config --services") printf 'api\ndashboard\nbrowser\n' ;;
		*" ps --status running --services")
			if [[ -n ${COMPOSE_RUNNING_MISMATCH:-} ]]; then
				printf 'api\ndashboard\n'
			else
				printf 'api\ndashboard\nbrowser\n'
			fi
			;;
	esac
fi
EOF
	chmod +x "$STUB_BIN/$command_name"
}

@test "missing required command fails verification" {
	rm "$STUB_BIN/nvim"

	run "$VERIFIER"

	[ "$status" -ne 0 ]
	[[ "$output" == *"missing command: nvim"* ]]
}

@test "runtime verification exercises Docker and Compose" {
	run "$VERIFIER" --runtime

	[ "$status" -eq 0 ]
	grep -q '^docker run --rm hello-world$' "$COMMAND_LOG"
	grep -q "^docker compose -f $DOTFILES_COMPOSE_FILE config$" "$COMMAND_LOG"
	grep -q "^docker compose -f $DOTFILES_COMPOSE_FILE ps --status running$" "$COMMAND_LOG"
}

@test "chezmoi drift fails verification" {
	export CHEZMOI_VERIFY_FAIL=1

	run "$VERIFIER"

	[ "$status" -ne 0 ]
	[[ "$output" == *"chezmoi target state differs"* ]]
}

@test "non-runtime verification does not run a test container" {
	run "$VERIFIER"

	[ "$status" -eq 0 ]
	! grep -q '^docker run ' "$COMMAND_LOG"
}

@test "missing running Compose service fails runtime verification" {
	export COMPOSE_RUNNING_MISMATCH=1

	run "$VERIFIER" --runtime

	[ "$status" -ne 0 ]
	[[ "$output" == *"not all Compose services are running"* ]]
}

@test "Linux verification checks System Manager and Docker systemd units" {
	export DOTFILES_VERIFY_PLATFORM=linux
	rm "$STUB_BIN/brew" "$STUB_BIN/darwin-rebuild"
	write_stub systemctl

	run "$VERIFIER"

	[ "$status" -eq 0 ]
	grep -q '^systemctl is-active --quiet system-manager.target$' "$COMMAND_LOG"
	grep -q '^systemctl is-active --quiet docker.service$' "$COMMAND_LOG"
	grep -q '^systemctl is-active --quiet docker.socket$' "$COMMAND_LOG"
}

@test "NixOS verification checks the current generation and Docker units" {
	export DOTFILES_VERIFY_PLATFORM=linux
	export DOTFILES_VERIFY_SYSTEM_LAYER=nixos
	export DOTFILES_CURRENT_SYSTEM_PATH="$BATS_TEST_TMPDIR/current-system"
	mkdir -p "$DOTFILES_CURRENT_SYSTEM_PATH"
	rm "$STUB_BIN/brew" "$STUB_BIN/darwin-rebuild"
	write_stub systemctl
	write_stub nixos-rebuild

	run "$VERIFIER"

	[ "$status" -eq 0 ]
	! grep -q 'system-manager.target' "$COMMAND_LOG"
	grep -q '^systemctl is-active --quiet docker.service$' "$COMMAND_LOG"
	grep -q '^systemctl is-active --quiet docker.socket$' "$COMMAND_LOG"
}
