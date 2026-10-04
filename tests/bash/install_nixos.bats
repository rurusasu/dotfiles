#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	INSTALLER="$REPO_ROOT/scripts/sh/install-nixos.sh"
	TEST_HOME="$BATS_TEST_TMPDIR/home"
	STUB_BIN="$BATS_TEST_TMPDIR/bin"
	COMMAND_LOG="$BATS_TEST_TMPDIR/commands.log"
	NIXOS_MARKER="$BATS_TEST_TMPDIR/NIXOS"
	CURRENT_SYSTEM="$BATS_TEST_TMPDIR/current-system"
	HARDWARE_CONFIG="$BATS_TEST_TMPDIR/hardware-configuration.nix"
	REAL_JQ="$(command -v jq)"
	mkdir -p "$TEST_HOME" "$STUB_BIN" "$CURRENT_SYSTEM"
	: >"$COMMAND_LOG"
	: >"$NIXOS_MARKER"
	printf '{ ... }: { fileSystems."/" = { device = "/dev/vda"; fsType = "ext4"; }; }\n' >"$HARDWARE_CONFIG"

	export HOME="$TEST_HOME"
	export USER="test-user"
	export PATH="$STUB_BIN:/usr/bin:/bin"
	export COMMAND_LOG STUB_BIN REAL_JQ REPO_ROOT
	export DOTFILES_SKIP_HERDR_INSTALL=1
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
	write_stub npm '
prefix="${NPM_CONFIG_PREFIX:-$HOME/.local/npm}"
mkdir -p "$prefix/bin"
printf "npm %s prefix=%s\n" "$*" "$prefix" >>"$COMMAND_LOG"
printf "#!/usr/bin/env bash\nexit 0\n" >"$prefix/bin/codex"
chmod +x "$prefix/bin/codex"
'
	write_stub jq 'exec "$REAL_JQ" "$@"'
	write_stub task '
printf "task %s\n" "$*" >>"$COMMAND_LOG"
case " $* " in
esac
'
	export DOTFILES_TASK_COMMAND="$STUB_BIN/task"
write_stub docker '
printf "docker %s\n" "$*" >>"$COMMAND_LOG"
case " $* " in
  *" info "*) [[ ${DOCKER_ENGINE_RUNNING:-0} == 1 ]] ;;
  *" network inspect bridge --format "*) printf "172.17.0.1\n" ;;
esac
'
	write_stub nc 'exit 0'
	write_stub curl '
printf "curl %s\n" "$*" >>"$COMMAND_LOG"
case "$*" in
  *"/api/tags"*) printf "%s\n" "{\"models\":[{\"name\":\"qwen3.6:35b\"},{\"name\":\"qwen3-embedding:0.6b\"}]}" ;;
  *"127.0.0.1:8888/health"*) printf "%s\n" "{\"status\":\"healthy\",\"database\":\"connected\"}" ;;
esac
exit 0
'
	write_stub ollama 'printf "ollama %s\n" "$*" >>"$COMMAND_LOG"'
	write_stub timeout '
if [[ ${1:-} == --version ]]; then
	printf "timeout (GNU coreutils) 9.0\n"
	exit 0
fi
[[ ${1:-} == --foreground ]] && shift
[[ ${1:-} == --kill-after=30 ]] && shift
shift
"$@"
'
	write_stub sleep 'exit 0'
	write_stub date 'echo 20260717010203'
	write_stub verify-environment '
printf "verify-environment layer=%s args=%s\n" "${DOTFILES_VERIFY_SYSTEM_LAYER:-}" "$*" >>"$COMMAND_LOG"
'
	ln -s "$REPO_ROOT" "$HOME/.dotfiles"
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

@test "NixOS rebuild activates native Hermes without starting the Docker gateway" {
	run "$INSTALLER"

	[ "$status" -eq 0 ]
	grep -q "nixos-rebuild user=test-user home=$HOME uid=1000 gid=1000 group=users args=switch --flake $REPO_ROOT#linux --impure" "$COMMAND_LOG"
	grep -q "DOTFILES_NIXOS_HARDWARE_CONFIG=$HARDWARE_CONFIG" "$COMMAND_LOG"
	grep -q "DOTFILES_WITH_HERMES=0" "$COMMAND_LOG"
	[ "$(line_of 'nix flake update --flake')" -lt "$(line_of nixos-rebuild)" ]
	[ "$(line_of nixos-rebuild)" -lt "$(line_of 'npm install --global --no-audit --no-fund @openai/codex@latest')" ]
	[ "$(line_of 'npm install --global --no-audit --no-fund @openai/codex@latest')" -lt "$(line_of 'chezmoi init')" ]
	[ "$(line_of nixos-rebuild)" -lt "$(line_of 'chezmoi init')" ]
	[ "$(line_of 'chezmoi apply')" -lt "$(line_of verify-environment)" ]
	grep -q '^verify-environment layer=nixos args=--nix-only$' "$COMMAND_LOG"
	! grep -q 'hermes:bootstrap\|docker compose.*hermes\|hermes-bootstrap' "$COMMAND_LOG"
}

@test "NixOS forwards an explicitly enabled Hermes feature to activation and verification" {
	export DOTFILES_WITH_HERMES=1

	run "$INSTALLER"

	[ "$status" -eq 0 ]
	grep -q "DOTFILES_WITH_HERMES=1" "$COMMAND_LOG"
	grep -q '^verify-environment layer=nixos args=--nix-only$' "$COMMAND_LOG"
}

@test "NixOS activation does not target a Docker Hermes gateway" {
	export DOCKER_ENGINE_RUNNING=1
	export DOTFILES_WITH_HERMES=1

	run "$INSTALLER"

	[ "$status" -eq 0 ]
	grep -q 'nixos-rebuild' "$COMMAND_LOG"
	! grep -q 'docker compose .* hermes' "$COMMAND_LOG"
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
	! grep -q '^docker compose ' "$COMMAND_LOG"
}

@test "NixOS native Hermes setup does not require Docker Compose" {
	rm -f "$STUB_BIN/docker"

	run "$INSTALLER"

	[ "$status" -eq 0 ]
	! grep -q '^docker ' "$COMMAND_LOG"
	! grep -q 'hermes:bootstrap\|hermes-bootstrap' "$COMMAND_LOG"
	grep -q '^verify-environment layer=nixos args=--nix-only$' "$COMMAND_LOG"
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

@test "NixOS Ollama is bridge reachable without opening its firewall port" {
	grep -q 'host = "0.0.0.0"' "$REPO_ROOT/nix/hosts/linux/configuration.nix"
	grep -q 'port = 11434' "$REPO_ROOT/nix/hosts/linux/configuration.nix"
	! grep -Eq 'allowedTCPPorts.*11434' "$REPO_ROOT/nix/hosts/linux/configuration.nix"
}
