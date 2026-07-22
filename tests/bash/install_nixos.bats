#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	INSTALLER="$REPO_ROOT/scripts/sh/install-nixos.sh"
	TEST_HOME="$BATS_TEST_TMPDIR/home"
	STUB_BIN="$BATS_TEST_TMPDIR/bin"
	COMMAND_LOG="$BATS_TEST_TMPDIR/commands.log"
	PAYLOAD_CAPTURE="$BATS_TEST_TMPDIR/payload.ndjson"
	NIXOS_MARKER="$BATS_TEST_TMPDIR/NIXOS"
	CURRENT_SYSTEM="$BATS_TEST_TMPDIR/current-system"
	HARDWARE_CONFIG="$BATS_TEST_TMPDIR/hardware-configuration.nix"
	REAL_JQ="$(command -v jq)"
	mkdir -p "$TEST_HOME" "$STUB_BIN" "$CURRENT_SYSTEM"
	: >"$COMMAND_LOG"
	: >"$PAYLOAD_CAPTURE"
	: >"$NIXOS_MARKER"
	printf '{ ... }: { fileSystems."/" = { device = "/dev/vda"; fsType = "ext4"; }; }\n' >"$HARDWARE_CONFIG"

	export HOME="$TEST_HOME"
	export USER="test-user"
	export PATH="$STUB_BIN:/usr/bin:/bin"
	export COMMAND_LOG STUB_BIN PAYLOAD_CAPTURE REAL_JQ
	export HERMES_SECRET_PLAN="$(valid_secret_plan)"
	export HERMES_ITEM_JSON='{"id":"fixture-item","fields":[]}'
	export HERMES_BOOTSTRAP_STATUS=0
	export DOTFILES_NIXOS_MARKER="$NIXOS_MARKER"
	export DOTFILES_CURRENT_SYSTEM_PATH="$CURRENT_SYSTEM"
	export DOTFILES_NIXOS_HARDWARE_CONFIG="$HARDWARE_CONFIG"
	export DOTFILES_WAIT_SLEEP_SECONDS=0
	export DOTFILES_VERIFY_ENVIRONMENT="$STUB_BIN/verify-environment"

	write_stub uname '
case "${1:-}" in
	-s) echo Linux ;;
	-m) echo x86_64 ;;
	*) exit 2 ;;
esac
'
	write_stub id '
case "${1:-}" in
	-u) echo 1000 ;;
	-g) echo 1000 ;;
	-gn) echo users ;;
	-Gn) echo "test-user docker" ;;
	*) /usr/bin/id "$@" ;;
esac
'
	write_stub nix '
printf "nix %s\n" "$*" >>"$COMMAND_LOG"
if [[ $* == "eval --impure --raw --expr builtins.currentSystem" ]]; then
	printf x86_64-linux
fi
'
	write_stub nixos-rebuild '
printf "nixos-rebuild user=%s home=%s uid=%s gid=%s group=%s args=%s\n" \
	"${DOTFILES_USER:-}" "${DOTFILES_HOME:-}" "${DOTFILES_UID:-}" \
	"${DOTFILES_GID:-}" "${DOTFILES_GROUP:-}" "$*" >>"$COMMAND_LOG"
'
	write_stub sudo '
printf "sudo %s\n" "$*" >>"$COMMAND_LOG"
exec "$@"
'
	write_stub chezmoi 'printf "chezmoi %s\n" "$*" >>"$COMMAND_LOG"'
	write_stub jq 'exec "$REAL_JQ" "$@"'
	write_stub op '
printf "op %s\n" "$*" >>"$COMMAND_LOG"
printf "%s\n" "$HERMES_ITEM_JSON"
'
	write_stub docker '
printf "docker %s\n" "$*" >>"$COMMAND_LOG"
case " $* " in
  *" hermes-bootstrap secret-plan "*) printf "%s\n" "$HERMES_SECRET_PLAN" ;;
  *" hermes-bootstrap apply "*) cat >"$PAYLOAD_CAPTURE"; exit "$HERMES_BOOTSTRAP_STATUS" ;;
esac
'
	write_stub nc 'exit 0'
	write_stub curl '
printf "curl %s\n" "$*" >>"$COMMAND_LOG"
exit 0
'
	write_stub sleep 'exit 0'
	write_stub date 'echo 20260717010203'
	write_stub verify-environment '
printf "verify-environment layer=%s args=%s\n" "${DOTFILES_VERIFY_SYSTEM_LAYER:-}" "$*" >>"$COMMAND_LOG"
'
	ln -s "$REPO_ROOT" "$HOME/.dotfiles"
}

valid_secret_plan() {
	cat <<'JSON'
{"schema_version":1,"items":[{"key":"dashboard","account":"my.1password.com","vault":"openclaw","item":"Hermes Agent Dashboard","fields":[{"canonical_name":"username","labels":["username"]}]},{"key":"github","account":"my.1password.com","vault":"openclaw","item":"GitHubUsedOpenClawPAT","fields":[{"canonical_name":"credential","labels":["credential"]}]},{"key":"slack_default","account":"my.1password.com","vault":"openclaw","item":"SlackBot-OpenClaw","fields":[{"canonical_name":"bot_token","labels":["SLACK_BOT_TOKEN"]}]},{"key":"slack_rick","account":"my.1password.com","vault":"openclaw","item":"SlackBot-Rick","fields":[{"canonical_name":"bot_token","labels":["SLACK_BOT_TOKEN"]}]},{"key":"slack_hoffman","account":"my.1password.com","vault":"openclaw","item":"SlackBot-Hoffman","fields":[{"canonical_name":"bot_token","labels":["SLACK_BOT_TOKEN"]}]},{"key":"slack_risarisa","account":"my.1password.com","vault":"openclaw","item":"SlackBot-Risarisa","fields":[{"canonical_name":"bot_token","labels":["SLACK_BOT_TOKEN"]}]}]}
JSON
}

write_stub() {
	local name="$1"
	local body="$2"
	cat >"$STUB_BIN/$name" <<EOF
#!/usr/bin/env bash
set -euo pipefail
$body
EOF
	chmod +x "$STUB_BIN/$name"
}

line_of() {
	grep -nF "$1" "$COMMAND_LOG" | head -1 | cut -d: -f1
}

@test "NixOS rebuilds then applies chezmoi Compose and acceptance" {
	run "$INSTALLER"

	[ "$status" -eq 0 ]
	grep -q "nixos-rebuild user=test-user home=$HOME uid=1000 gid=1000 group=users args=switch --flake $REPO_ROOT#linux --impure" "$COMMAND_LOG"
	grep -q "DOTFILES_NIXOS_HARDWARE_CONFIG=$HARDWARE_CONFIG" "$COMMAND_LOG"
	[ "$(line_of nixos-rebuild)" -lt "$(line_of 'chezmoi init')" ]
	[ "$(line_of 'chezmoi apply')" -lt "$(line_of 'docker compose')" ]
	[ "$(line_of "docker compose -f $REPO_ROOT/docker/hermes-agent/compose.yml config --quiet")" -lt "$(line_of "docker compose -f $REPO_ROOT/docker/hermes-agent/compose.yml build hermes hermes-bootstrap")" ]
	[ "$(line_of "docker compose -f $REPO_ROOT/docker/hermes-agent/compose.yml build hermes hermes-bootstrap")" -lt "$(line_of "docker compose -f $REPO_ROOT/docker/hermes-agent/compose.yml stop hermes")" ]
	[ "$(line_of "docker compose -f $REPO_ROOT/docker/hermes-agent/compose.yml stop hermes")" -lt "$(line_of 'hermes-bootstrap secret-plan')" ]
	[ "$(line_of 'hermes-bootstrap secret-plan')" -lt "$(line_of 'hermes-bootstrap apply')" ]
	[ "$(line_of 'hermes-bootstrap apply')" -lt "$(line_of "docker compose -f $REPO_ROOT/docker/hermes-agent/compose.yml up -d --force-recreate")" ]
	[ "$(line_of 'docker compose')" -lt "$(line_of verify-environment)" ]
	grep -q '^verify-environment layer=nixos args=--runtime$' "$COMMAND_LOG"
	[ "$(grep -c '^op item get ' "$COMMAND_LOG")" -eq 6 ]
	[ -s "$PAYLOAD_CAPTURE" ]
}

@test "Hermes bootstrap failure stops NixOS before service recreation and acceptance" {
	export HERMES_BOOTSTRAP_STATUS=45

	run "$INSTALLER"

	[ "$status" -eq 45 ]
	grep -q 'hermes-bootstrap apply' "$COMMAND_LOG"
	! grep -q ' up -d --force-recreate' "$COMMAND_LOG"
	! grep -q '^verify-environment ' "$COMMAND_LOG"
}

@test "NixOS refuses activation without a readable hardware profile" {
	export DOTFILES_NIXOS_HARDWARE_CONFIG="$BATS_TEST_TMPDIR/missing-hardware.nix"

	run "$INSTALLER"

	[ "$status" -ne 0 ]
	[[ "$output" == *"NixOS hardware configuration is missing"* ]]
	! grep -q '^nixos-rebuild ' "$COMMAND_LOG"
}

@test "NixOS E2E can activate an already built system through the real installer" {
	prebuilt="$BATS_TEST_TMPDIR/prebuilt-system"
	mkdir -p "$prebuilt/bin"
	cat >"$prebuilt/bin/switch-to-configuration" <<'EOF'
#!/usr/bin/env bash
printf 'switch-to-configuration %s\n' "$*" >>"$COMMAND_LOG"
EOF
	chmod +x "$prebuilt/bin/switch-to-configuration"
	export DOTFILES_NIXOS_PREBUILT_SYSTEM="$prebuilt"

	run "$INSTALLER"

	[ "$status" -eq 0 ]
	grep -q '^switch-to-configuration switch$' "$COMMAND_LOG"
	! grep -q '^nixos-rebuild ' "$COMMAND_LOG"
}

@test "NixOS rebuild failure stops before user configuration" {
	write_stub nixos-rebuild '
printf "nixos-rebuild %s\n" "$*" >>"$COMMAND_LOG"
exit 42
'

	run "$INSTALLER"

	[ "$status" -eq 42 ]
	! grep -q '^chezmoi ' "$COMMAND_LOG"
	! grep -q '^docker ' "$COMMAND_LOG"
}

@test "NixOS Compose failure stops before acceptance" {
	write_stub docker '
printf "docker %s\n" "$*" >>"$COMMAND_LOG"
case " $* " in
  *" hermes-bootstrap secret-plan "*) printf "%s\n" "$HERMES_SECRET_PLAN" ;;
  *" hermes-bootstrap apply "*) cat >"$PAYLOAD_CAPTURE" ;;
  *" up -d --force-recreate "*) exit 43 ;;
esac
'

	run "$INSTALLER"

	[ "$status" -eq 43 ]
	grep -q ' ps --all$' "$COMMAND_LOG"
	! grep -q '^verify-environment ' "$COMMAND_LOG"
}

@test "NixOS acceptance failure is propagated" {
	write_stub verify-environment '
printf "verify-environment %s\n" "$*" >>"$COMMAND_LOG"
exit 44
'

	run "$INSTALLER"

	[ "$status" -eq 44 ]
}

@test "NixOS host manages current identity Docker Compose and Buildx" {
	grep -q 'DOTFILES_USER' "$REPO_ROOT/nix/hosts/linux/configuration.nix"
	grep -q 'DOTFILES_UID' "$REPO_ROOT/nix/hosts/linux/configuration.nix"
	grep -q 'DOTFILES_GROUP' "$REPO_ROOT/nix/hosts/linux/configuration.nix"
	grep -q 'virtualisation.docker.enable = true' "$REPO_ROOT/nix/hosts/linux/configuration.nix"
	grep -q 'docker-compose' "$REPO_ROOT/nix/hosts/linux/configuration.nix"
	grep -q 'docker-buildx' "$REPO_ROOT/nix/hosts/linux/configuration.nix"
	! grep -q 'rootless' "$REPO_ROOT/nix/hosts/linux/configuration.nix"
	! grep -q '/dev/sda' "$REPO_ROOT/nix/hosts/linux/configuration.nix"
	! grep -q 'fileSystems\."/"' "$REPO_ROOT/nix/hosts/linux/configuration.nix"
}
