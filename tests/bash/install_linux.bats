#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	INSTALLER="$REPO_ROOT/scripts/sh/install-linux.sh"
	FALLBACK_INSTALLER="$REPO_ROOT/scripts/sh/install-home-manager.sh"
	TEST_HOME="$BATS_TEST_TMPDIR/home"
	STUB_BIN="$BATS_TEST_TMPDIR/bin"
	COMMAND_LOG="$BATS_TEST_TMPDIR/commands.log"
	PAYLOAD_CAPTURE="$BATS_TEST_TMPDIR/payload.ndjson"
	FAKE_NIX_PROFILE="$BATS_TEST_TMPDIR/nix-daemon.sh"
	FAKE_SYSTEMD_DIR="$BATS_TEST_TMPDIR/systemd/system"
	OS_RELEASE="$BATS_TEST_TMPDIR/os-release"
	REAL_JQ="$(command -v jq)"
	mkdir -p "$TEST_HOME" "$STUB_BIN" "$FAKE_SYSTEMD_DIR"
	: >"$COMMAND_LOG"
	: >"$PAYLOAD_CAPTURE"
	: >"$FAKE_NIX_PROFILE"
	printf 'ID=ubuntu\n' >"$OS_RELEASE"

	export HOME="$TEST_HOME"
	export USER="test-user"
	export PATH="$STUB_BIN:/usr/bin:/bin"
	export COMMAND_LOG STUB_BIN PAYLOAD_CAPTURE REAL_JQ
	export DOTFILES_SKIP_HERDR_INSTALL=1
	export HERMES_SECRET_PLAN="$(valid_secret_plan)"
	export HERMES_ITEM_JSON='{"id":"fixture-item","fields":[]}'
	export HERMES_XAPI_ITEM_JSON='{"id":"xapi-item","fields":[{"label":"X_API_CLIENT_ID","value":"xapi-client-id-marker"},{"label":"X_API_CLIENT_SECRET","value":"xapi-client-secret-marker"}]}'
	export HERMES_BOOTSTRAP_STATUS=0
	export DOTFILES_NIX_PROFILE_SCRIPT="$FAKE_NIX_PROFILE"
	export DOTFILES_SYSTEMD_DIR="$FAKE_SYSTEMD_DIR"
	export DOTFILES_OS_RELEASE_FILE="$OS_RELEASE"
	export DOTFILES_WAIT_SLEEP_SECONDS=0
	export DOTFILES_SYSTEMD_WAIT_ATTEMPTS=2
	export DOTFILES_VERIFY_ENVIRONMENT="$STUB_BIN/verify-environment"

	write_stub uname '
case "${1:-}" in
	-s) echo Linux ;;
	-m) echo x86_64 ;;
	*) exit 2 ;;
esac
'
	write_stub systemctl '
printf "systemctl %s\n" "$*" >>"$COMMAND_LOG"
case "$*" in
	"is-system-running") echo running ;;
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
	write_stub nc 'exit 0'
	write_stub curl '
printf "curl %s\n" "$*" >>"$COMMAND_LOG"
case "$*" in
  *"/api/tags"*) printf "%s\n" "{\"models\":[{\"name\":\"qwen3.6:35b\"},{\"name\":\"qwen3-embedding:0.6b\"}]}"; exit 0 ;;
  *"127.0.0.1:8888/health"*) printf "%s\n" "{\"status\":\"healthy\",\"database\":\"connected\"}"; exit 0 ;;
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
exec "$@"
'
	write_stub sleep 'exit 0'
	write_stub date 'echo 20260717010203'
	write_stub chezmoi 'printf "chezmoi %s\n" "$*" >>"$COMMAND_LOG"'
	write_stub jq 'exec "$REAL_JQ" "$@"'
	write_stub op '
printf "op %s\n" "$*" >>"$COMMAND_LOG"
if [ "${3:-}" = "Hermes X API MCP" ]; then
	printf "%s\n" "$HERMES_XAPI_ITEM_JSON"
else
	printf "%s\n" "$HERMES_ITEM_JSON"
fi
'
	write_stub docker '
printf "docker %s\n" "$*" >>"$COMMAND_LOG"
case " $* " in
  *" network inspect bridge --format "*) printf "172.17.0.1\n" ;;
  *" ps --all --services hermes "*) printf "hermes\n" ;;
  *" hermes-bootstrap secret-plan "*) printf "%s\n" "$HERMES_SECRET_PLAN" ;;
  *" hermes-bootstrap apply "*) cat >"$PAYLOAD_CAPTURE"; exit "$HERMES_BOOTSTRAP_STATUS" ;;
esac
'
	write_stub verify-environment 'printf "verify-environment %s\n" "$*" >>"$COMMAND_LOG"'
	write_stub sg '
printf "sg %s\n" "$*" >>"$COMMAND_LOG"
[ "${2:-}" = "-c" ]
exec bash -c "$3"
'
}

valid_secret_plan() {
	cat <<'JSON'
{"schema_version":1,"items":[{"key":"dashboard","account":"my.1password.com","vault":"openclaw","item":"Hermes Agent Dashboard","fields":[{"canonical_name":"username","labels":["username"]}]},{"key":"github","account":"my.1password.com","vault":"openclaw","item":"GitHubUsedOpenClawPAT","fields":[{"canonical_name":"credential","labels":["credential"]}]},{"key":"google_calendar","account":"my.1password.com","vault":"Private","item":"Google Calendar MCP","fields":[{"canonical_name":"oauth_credentials_json","labels":["oauth_credentials_json"]},{"canonical_name":"tokens_json","labels":["tokens_json"]}]},{"key":"discord_default","account":"my.1password.com","vault":"openclaw","item":"Master","fields":[{"canonical_name":"bot_token","labels":["DISCORD_BOT_TOKEN"]}]},{"key":"discord_rick","account":"my.1password.com","vault":"openclaw","item":"Rick","fields":[{"canonical_name":"bot_token","labels":["DISCORD_BOT_TOKEN"]}]},{"key":"discord_hoffman","account":"my.1password.com","vault":"openclaw","item":"Hoffman","fields":[{"canonical_name":"bot_token","labels":["DISCORD_BOT_TOKEN"]}]},{"key":"discord_risarisa","account":"my.1password.com","vault":"openclaw","item":"RisaRisa","fields":[{"canonical_name":"bot_token","labels":["DISCORD_BOT_TOKEN"]}]},{"key":"discord_nancy","account":"my.1password.com","vault":"openclaw","item":"Nancy","fields":[{"canonical_name":"bot_token","labels":["DISCORD_BOT_TOKEN"]}]},{"key":"discord_kuroda","account":"my.1password.com","vault":"openclaw","item":"Kuroda","fields":[{"canonical_name":"bot_token","labels":["DISCORD_BOT_TOKEN"]}]},{"key":"discord_shiraishi","account":"my.1password.com","vault":"openclaw","item":"Shiraishi","fields":[{"canonical_name":"bot_token","labels":["DISCORD_BOT_TOKEN"]}]}]}
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

write_nix_stub() {
	write_stub nix '
printf "nix user=%s home=%s uid=%s gid=%s group=%s system=%s args=%s\n" \
	"${DOTFILES_USER:-}" "${DOTFILES_HOME:-}" "${DOTFILES_UID:-}" \
	"${DOTFILES_GID:-}" "${DOTFILES_GROUP:-}" "${DOTFILES_SYSTEM:-}" "$*" >>"$COMMAND_LOG"
if [[ $* == "eval --impure --raw --expr builtins.currentSystem" ]]; then
	printf "x86_64-linux"
fi
'
}

write_fresh_nix_installer_stub() {
	write_stub curl '
printf "curl %s\n" "$*" >>"$COMMAND_LOG"
case "$*" in
  *"/api/tags"*) printf "%s\n" "{\"models\":[{\"name\":\"qwen3.6:35b\"},{\"name\":\"qwen3-embedding:0.6b\"}]}"; exit 0 ;;
  *"127.0.0.1:8888/health"*) printf "%s\n" "{\"status\":\"healthy\",\"database\":\"connected\"}"; exit 0 ;;
  *"/health"*) exit 0 ;;
esac
cat <<'"'"'SCRIPT'"'"'
printf "nix-installer %s\n" "$*" >>"$COMMAND_LOG"
cat >"$STUB_BIN/nix" <<'"'"'NIX'"'"'
#!/usr/bin/env bash
set -euo pipefail
printf "nix user=%s home=%s uid=%s gid=%s group=%s system=%s args=%s\n" \
	"${DOTFILES_USER:-}" "${DOTFILES_HOME:-}" "${DOTFILES_UID:-}" \
	"${DOTFILES_GID:-}" "${DOTFILES_GROUP:-}" "${DOTFILES_SYSTEM:-}" "$*" >>"$COMMAND_LOG"
if [[ $* == "eval --impure --raw --expr builtins.currentSystem" ]]; then
	printf "x86_64-linux"
fi
NIX
chmod +x "$STUB_BIN/nix"
SCRIPT
'
}

assert_log_order() {
	local previous=0 pattern line
	for pattern in "$@"; do
		line="$(grep -nF "$pattern" "$COMMAND_LOG" | head -1 | cut -d: -f1)"
		[ -n "$line" ]
		[ "$line" -gt "$previous" ]
		previous="$line"
	done
}

@test "Ubuntu applies System Manager then chezmoi Compose and acceptance" {
	write_nix_stub

	run "$INSTALLER"

	[ "$status" -eq 0 ]
	grep -q 'user=test-user home=.* uid=1000 gid=1000 group=users system=x86_64-linux args=run .#system-manager -- --nix-option pure-eval false switch --flake .#ubuntu --sudo' "$COMMAND_LOG"
	assert_log_order \
		"args=flake update --flake $REPO_ROOT" \
		"switch --flake .#ubuntu --sudo" \
		"chezmoi init --source $REPO_ROOT/chezmoi" \
		"chezmoi apply --force" \
		"docker compose -f $REPO_ROOT/docker/hermes-agent/compose.yml config --quiet" \
		"docker compose -f $REPO_ROOT/docker/hermes-agent/compose.yml build --pull hermes hermes-bootstrap chromium xapi-mcp" \
		"docker compose -f $REPO_ROOT/docker/hermes-agent/compose.yml stop hermes" \
		"docker compose -f $REPO_ROOT/docker/hermes-agent/compose.yml run --rm --no-deps -T hermes-bootstrap secret-plan" \
		"docker compose -f $REPO_ROOT/docker/hermes-agent/compose.yml run --rm --no-deps -T hermes-bootstrap apply" \
		"docker compose -f $REPO_ROOT/docker/hermes-agent/compose.yml up -d --force-recreate" \
		"docker image prune --force" \
		"verify-environment --runtime"
	[ "$(grep -c '^op item get ' "$COMMAND_LOG")" -eq 11 ]
	[ "$(grep -c '^op signin --account my.1password.com$' "$COMMAND_LOG")" -eq 1 ]
	[ -s "$PAYLOAD_CAPTURE" ]
}

@test "flake update failure stops Linux activation" {
	write_stub nix '
printf "nix %s\n" "$*" >>"$COMMAND_LOG"
if [[ $* == flake\ update\ --flake\ * ]]; then
  exit 42
fi
if [[ $* == "eval --impure --raw --expr builtins.currentSystem" ]]; then
  printf x86_64-linux
fi
'

	run "$INSTALLER"

	[ "$status" -eq 42 ]
	! grep -q 'switch --flake' "$COMMAND_LOG"
	! grep -q '^chezmoi ' "$COMMAND_LOG"
}

@test "flake update can be skipped for offline test environments" {
	export DOTFILES_SKIP_FLAKE_UPDATE=1
	write_nix_stub

	run "$INSTALLER"

	[ "$status" -eq 0 ]
	! grep -q 'args=flake update --flake' "$COMMAND_LOG"
	grep -q 'switch --flake .#ubuntu --sudo' "$COMMAND_LOG"
}

@test "Hermes bootstrap failure recovers Linux runtime before returning failure" {
	write_nix_stub
	export HERMES_BOOTSTRAP_STATUS=45

	run "$INSTALLER"

	[ "$status" -eq 45 ]
	grep -q 'hermes-bootstrap apply' "$COMMAND_LOG"
	! grep -q ' up -d --force-recreate' "$COMMAND_LOG"
	grep -q ' start' "$COMMAND_LOG"
	! grep -q ' up ' "$COMMAND_LOG"
	! grep -q '^verify-environment ' "$COMMAND_LOG"
}

@test "Linux accepts a responsive systemd manager while the global state is starting" {
	write_nix_stub
	write_stub systemctl '
printf "systemctl %s\n" "$*" >>"$COMMAND_LOG"
case "$*" in
"is-system-running") echo starting ;;
"show --property=Version --value") echo 255.4 ;;
esac
'

	run "$INSTALLER"

	[ "$status" -eq 0 ]
	[ "$(grep -c '^systemctl is-system-running$' "$COMMAND_LOG")" -eq 1 ]
	grep -q '^systemctl show --property=Version --value$' "$COMMAND_LOG"
}

@test "Linux waits when a starting systemd manager is not yet responsive" {
	write_nix_stub
	state_count="$BATS_TEST_TMPDIR/systemd-state-count"
	printf '0\n' >"$state_count"
	export STATE_COUNT="$state_count"
	write_stub systemctl '
printf "systemctl %s\n" "$*" >>"$COMMAND_LOG"
if [[ $* == "is-system-running" ]]; then
	count="$(cat "$STATE_COUNT")"
	count=$((count + 1))
	printf "%s\n" "$count" >"$STATE_COUNT"
	if ((count == 1)); then echo starting; else echo running; fi
fi
'

	run "$INSTALLER"

	[ "$status" -eq 0 ]
	[ "$(grep -c '^systemctl is-system-running$' "$COMMAND_LOG")" -eq 2 ]
}

@test "Debian selects the Debian System Manager output" {
	printf 'ID=debian\n' >"$OS_RELEASE"
	write_nix_stub

	run "$INSTALLER"

	[ "$status" -eq 0 ]
	grep -q 'switch --flake .#debian --sudo' "$COMMAND_LOG"
}

@test "fresh Linux setup installs Nix once and reruns idempotently" {
	write_fresh_nix_installer_stub

	run "$INSTALLER"
	[ "$status" -eq 0 ]
	run "$INSTALLER"
	[ "$status" -eq 0 ]

	[ "$(grep -c '^nix-installer --daemon$' "$COMMAND_LOG")" -eq 1 ]
	[ "$(grep -c 'switch --flake .#ubuntu --sudo' "$COMMAND_LOG")" -eq 2 ]
}

@test "System Manager failure stops before user and runtime phases" {
	write_nix_stub
	cat >>"$STUB_BIN/nix" <<'EOF'
if [[ $* == *"switch --flake"* ]]; then exit 42; fi
EOF

	run "$INSTALLER"

	[ "$status" -eq 42 ]
	! grep -q '^chezmoi ' "$COMMAND_LOG"
	! grep -q '^docker compose ' "$COMMAND_LOG"
}

@test "invalid existing user identity is rejected before System Manager" {
	write_nix_stub
	write_stub id '
case "${1:-}" in
	-u) echo not-a-number ;;
	-g) echo 1000 ;;
	-gn) echo users ;;
	-Gn) echo "test-user docker" ;;
esac
'

	run "$INSTALLER"

	[ "$status" -ne 0 ]
	[[ "$output" == *"numeric UID/GID"* ]]
	! grep -q 'switch --flake' "$COMMAND_LOG"
}

@test "a stale shell enters the declared docker group for runtime commands" {
	write_nix_stub
	write_stub id '
case "${1:-}" in
	-u) echo 1000 ;;
	-g) echo 1000 ;;
	-gn) echo users ;;
	-Gn)
		if [ "$#" -gt 1 ]; then echo "test-user docker"; else echo test-user; fi
		;;
	*) /usr/bin/id "$@" ;;
esac
'

	run "$INSTALLER"

	[ "$status" -eq 0 ]
	grep -q '^sg docker -c ' "$COMMAND_LOG"
}

@test "Home Manager fallback requires direct explicit opt-in" {
	write_nix_stub

	run "$FALLBACK_INSTALLER"

	[ "$status" -ne 0 ]
	[[ "$output" == *"DOTFILES_ALLOW_USER_ONLY=1"* ]]
}

@test "Home Manager fallback activates only the user environment" {
	export DOTFILES_ALLOW_USER_ONLY=1
	activation="$BATS_TEST_TMPDIR/home-manager-generation"
	mkdir -p "$activation"
	cat >"$activation/activate" <<EOF
#!/usr/bin/env bash
printf 'home-manager-activate\n' >>"$COMMAND_LOG"
EOF
	chmod +x "$activation/activate"
	write_stub nix "
printf 'nix %s\\n' \"\$*\" >>\"\$COMMAND_LOG\"
if [[ \$* == 'eval --impure --raw --expr builtins.currentSystem' ]]; then
	printf x86_64-linux
elif [[ \$* == *homeConfigurations*activationPackage* ]]; then
	printf '$activation\\n'
fi
"

	run "$FALLBACK_INSTALLER"

	[ "$status" -eq 0 ]
	grep -q 'build --impure --no-link --print-out-paths .*homeConfigurations.*x86_64-linux.*activationPackage' "$COMMAND_LOG"
	assert_log_order \
		"nix flake update --flake $REPO_ROOT" \
		"homeConfigurations" \
		"home-manager-activate" \
		"chezmoi init --source $REPO_ROOT/chezmoi" \
		"chezmoi apply --force"
	! grep -q '^docker ' "$COMMAND_LOG"
	! grep -q '^verify-environment ' "$COMMAND_LOG"
	[[ "$output" == *"User-only setup complete; Docker/systemd were not configured."* ]]
}
