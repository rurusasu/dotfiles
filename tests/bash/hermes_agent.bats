#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	TEST_HOME="$BATS_TEST_TMPDIR/home"
	STUB_BIN="$BATS_TEST_TMPDIR/bin"
	COMMAND_LOG="$BATS_TEST_TMPDIR/commands.log"
	EDIT_CAPTURE="$BATS_TEST_TMPDIR/item-edit.json"
	OP_TOKEN_CAPTURE="$BATS_TEST_TMPDIR/op-token.log"
	READY_ATTEMPT_FILE="$BATS_TEST_TMPDIR/ready-attempts"
	XAPI_TOKEN_ATTEMPT_FILE="$BATS_TEST_TMPDIR/xapi-token-attempts"
	COMPOSE_FILE="$BATS_TEST_TMPDIR/docker/hermes-service/compose file.yml"
	REAL_JQ="$(command -v jq)"
	REAL_PYTHON3="$(command -v python3)"
	REAL_GIT="$(command -v git)"
	export REAL_INSTALL_TASK="$(command -v task)"
	SECRET_MARKER="adapter-secret-marker"
	mkdir -p "$TEST_HOME/.hermes" "$STUB_BIN"
	: >"$COMMAND_LOG"
	: >"$OP_TOKEN_CAPTURE"
	printf '0\n' >"$READY_ATTEMPT_FILE"
	printf '0\n' >"$XAPI_TOKEN_ATTEMPT_FILE"
	mkdir -p "$(dirname "$COMPOSE_FILE")" "$BATS_TEST_TMPDIR/nix/modules/hermes-agent"
	cp "$REPO_ROOT/nix/modules/hermes-agent/manifest.yaml" \
		"$BATS_TEST_TMPDIR/nix/modules/hermes-agent/manifest.yaml"
	: >"$COMPOSE_FILE"

	export REPO_ROOT HOME="$TEST_HOME" PATH="$STUB_BIN:/usr/bin:/bin"
	unset DOTFILES_USER SUDO_USER
	unset OP_SERVICE_ACCOUNT_TOKEN
	export COMMAND_LOG EDIT_CAPTURE OP_TOKEN_CAPTURE READY_ATTEMPT_FILE XAPI_TOKEN_ATTEMPT_FILE COMPOSE_FILE REAL_JQ REAL_PYTHON3 SECRET_MARKER
	export OP_ITEM_JSON='{"id":"item-id","fields":[{"label":"credential","value":"adapter-secret-marker"}]}'
	export XAPI_OP_ITEM_JSON='{"id":"xapi-item","fields":[{"label":"X_API_CLIENT_ID","value":"xapi-client-id-marker"},{"label":"X_API_CLIENT_SECRET","value":"xapi-client-secret-marker"},{"label":"X_API_REFRESH_TOKEN","section":{"label":"Refresh Token"},"value":"xapi-refresh-token-marker"}]}'
	export XAPI_OAUTH_ITEM_JSON='{"id":"xapi-oauth-item","fields":[{"label":"X_API_REFRESH_TOKEN","value":"xapi-refresh-token-marker"}]}'
	export OP_FAIL_ITEM=""
	export OP_EDIT_STATUS=0
	export OP_DELAY_SECONDS=0
	export OP_READ_TOKEN='service-account-token'
	export OP_READ_DELAY_SECONDS=0
	export OP_READ_COMPLETION_FILE=""
	export API_READY_AFTER=1
	export HERMES_API_READY_ATTEMPTS=3
	export HERMES_API_READY_DELAY_SECONDS=0
	export HERMES_API_PROBE_TIMEOUT_SECONDS=1
	export XAPI_TOKEN_READY_AFTER=1
	export XAPI_TOKEN_FAILURE_KIND=auth
	export XAPI_TOKEN_FAILURE_STATUS=1
	export XAPI_ROTATED_REFRESH_TOKEN=""
	export UP_STATUS=0

	write_stub jq '
exec "$REAL_JQ" "$@"
'
	write_stub python3 'exec "$REAL_PYTHON3" "$@"'
	write_stub op '
printf "op" >>"$COMMAND_LOG"
printf " <%s>" "$@" >>"$COMMAND_LOG"
printf "\n" >>"$COMMAND_LOG"
	case "${3:-}" in
	read)
		if [[ ${OP_READ_DELAY_SECONDS:-0} != 0 ]]; then
			/bin/sleep "$OP_READ_DELAY_SECONDS"
		fi
		if [[ -n ${OP_READ_COMPLETION_FILE:-} ]]; then
			printf "completed\n" >"$OP_READ_COMPLETION_FILE"
		fi
		printf "%s\n" "$OP_READ_TOKEN"
		;;
	*)
		if [ "${1:-}" = item ] && [ "${2:-}" = edit ]; then
			if [ "${8:-}" = --template ]; then
				cat "${9:?}" >"$EDIT_CAPTURE"
			else
				cat >"$EDIT_CAPTURE"
			fi
			exit "$OP_EDIT_STATUS"
		fi
		[ "${2:-}" = get ] || exit 2
		printf "%s\n" "${OP_SERVICE_ACCOUNT_TOKEN:-<unset>}" >>"$OP_TOKEN_CAPTURE"
		if [ "${3:-}" = "$OP_FAIL_ITEM" ]; then
			exit 17
		fi
		if [[ $OP_DELAY_SECONDS != 0 ]]; then
			/bin/sleep "$OP_DELAY_SECONDS"
		fi
		if [ "${3:-}" = "Hermes X API MCP" ]; then
			printf "%s\n" "$XAPI_OP_ITEM_JSON"
		elif [ "${3:-}" = "Hermes X API MCP OAuth" ]; then
			printf "%s\n" "$XAPI_OAUTH_ITEM_JSON"
		else
			printf "%s\n" "$OP_ITEM_JSON"
		fi
		;;
esac
'
	write_stub docker '
printf "docker" >>"$COMMAND_LOG"
printf " <%s>" "$@" >>"$COMMAND_LOG"
printf "\n" >>"$COMMAND_LOG"
if [ "${1:-}" != "compose" ]; then
	exit 1
fi
case " $* " in
  *" run --rm --no-deps --entrypoint /bin/sh xapi-mcp "*)
	attempt="$(cat "$XAPI_TOKEN_ATTEMPT_FILE")"
	attempt=$((attempt + 1))
	printf "%s\n" "$attempt" >"$XAPI_TOKEN_ATTEMPT_FILE"
	if ((attempt < XAPI_TOKEN_READY_AFTER)); then
		if [[ $XAPI_TOKEN_FAILURE_KIND == auth ]]; then
			printf "%s\n" "Error: no valid oauth2 token for app default: Auth Error: TokenNotFound (cause: oauth2 token not found)" >&2
			printf "%s\n" "Run: xurl auth oauth2" >&2
		else
			printf "%s\n" "Cannot connect to the Docker daemon." >&2
		fi
		exit "$XAPI_TOKEN_FAILURE_STATUS"
	fi
	if [[ -n ${XAPI_ROTATED_REFRESH_TOKEN:-} ]]; then
		sed -i.bak "s/refresh_token:.*/refresh_token: \"$XAPI_ROTATED_REFRESH_TOKEN\"/" "$HOME/.hermes/.xurl/auth.yml"
		rm -f "$HOME/.hermes/.xurl/auth.yml.bak"
	fi
	exit 0
	;;
  *" up -d --force-recreate "*)
    exit "$UP_STATUS"
    ;;
esac
'
	write_stub curl '
attempt="$(cat "$READY_ATTEMPT_FILE")"
attempt=$((attempt + 1))
printf "%s\n" "$attempt" >"$READY_ATTEMPT_FILE"
printf "curl" >>"$COMMAND_LOG"
printf " <%s>" "$@" >>"$COMMAND_LOG"
printf "\n" >>"$COMMAND_LOG"
if ((attempt < API_READY_AFTER)); then
	exit 22
fi
'
	write_stub timeout '
if [[ ${1:-} == --version ]]; then
	printf "timeout (GNU coreutils) 9.0\n"
	exit 0
fi
printf "timeout" >>"$COMMAND_LOG"
printf " <%s>" "$@" >>"$COMMAND_LOG"
printf "\n" >>"$COMMAND_LOG"
[[ ${1:-} == --foreground ]] && shift
[[ ${1:-} == --kill-after=30 ]] && shift
shift
"$@"
'
	write_stub sleep '
printf "sleep <%s>\n" "$*" >>"$COMMAND_LOG"
'
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

run_restart_sidecar() {
	local missing_command="${1:-}"
	if [[ -z $missing_command ]]; then
		run env HERMES_COMPOSE_FILE="$COMPOSE_FILE" bash "$REPO_ROOT/scripts/sh/hermes-xapi.sh" restart
		return
	fi
	run env DOTFILES_TEST_MISSING_COMMAND="$missing_command" bash -c '
set -euo pipefail
. "$REPO_ROOT/scripts/sh/install-common.sh"
. "$REPO_ROOT/scripts/sh/hermes-sidecar-common.sh"
if [[ -n ${DOTFILES_TEST_MISSING_COMMAND:-} ]]; then
  dotfiles_have() {
    [[ $1 != "$DOTFILES_TEST_MISSING_COMMAND" ]] && command -v "$1" >/dev/null 2>&1
  }
fi
dotfiles_hermes_require_xapi_tools
dotfiles_hermes_prepare_runtime_home
dotfiles_hermes_ensure_xapi_auth docker "$COMPOSE_FILE"
dotfiles_hermes_with_xapi_credentials_and_cache \
  docker compose -f "$COMPOSE_FILE" up -d --force-recreate xapi-mcp
'
}

service_account_cache_mode() {
	stat -c '%a' "$HOME/.hermes/.op.env" 2>/dev/null ||
		stat -f '%Lp' "$HOME/.hermes/.op.env"
}

service_account_cache_inode() {
	stat -c '%i' "$1" 2>/dev/null || stat -f '%i' "$1"
}

assert_service_account_cache_rejected_after_timeout() {
	export OP_READ_DELAY_SECONDS=2 DOTFILES_HERMES_OP_READ_TIMEOUT_SECONDS=1
	run_restart_sidecar
	[ "$status" -ne 0 ]
	! grep -q '<compose>' "$COMMAND_LOG"
}

@test "Unix installers leave Hermes configuration to Nix" {
	for file in "$REPO_ROOT/install.sh" "$REPO_ROOT/scripts/sh/install-macos.sh" "$REPO_ROOT/scripts/sh/install-nixos.sh"; do
		! grep -Fq 'hermes:bootstrap' "$file"
		! grep -Fq 'docker compose' "$file"
		! grep -Fq 'npm install' "$file"
	done
}

@test "hermes:bootstrap activates the Nix-managed Hermes profile" {
	local bootstrap_task
	bootstrap_task="$(awk '
		/^  hermes:bootstrap:$/ { in_task = 1 }
		in_task && /^  [^ ]/ && $0 !~ /^  hermes:bootstrap:/ { exit }
		in_task { print }
	' "$REPO_ROOT/taskfiles/hermes/taskfile.yml")"

	[[ "$bootstrap_task" == *'sudo nixos-rebuild switch --flake . --impure'* ]]
	[[ "$bootstrap_task" == *'task darwin:install'* ]]
	[[ "$bootstrap_task" != *'hermes:docker:bootstrap'* ]]
	[[ "$bootstrap_task" != *'docker compose'* ]]
}

@test "NixOS-WSL Hermes readiness requires every critical check" {
	local readiness_script required_checks
	readiness_script="$(<"$REPO_ROOT/scripts/powershell/ci/Invoke-NixosWslE2E.ps1")"
	required_checks='["state_db", "session_store", "config", "model", "disk", "gateway", "background_queues"]'

	[[ "$readiness_script" == *"$required_checks"* ]]
	[[ "$readiness_script" == *'type == "object" and .status == "ok"'* ]]
	[[ "$readiness_script" == *'all(.[]; .status == "ok")'* ]]
}

@test "preserves Hermes data and browser directory helpers" {
	export HERMES_DATA_DIR="$TEST_HOME/custom-data"
	export HERMES_BROWSER_DATA_DIR="$TEST_HOME/custom-browser"

	run bash -c '
set -euo pipefail
. "$REPO_ROOT/scripts/sh/install-common.sh"
. "$REPO_ROOT/scripts/sh/hermes-sidecar-common.sh"
printf "%s\n%s\n" "$(dotfiles_hermes_data_dir)" "$(dotfiles_hermes_browser_data_dir)"
dotfiles_hermes_prepare_runtime_home
'

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "$TEST_HOME/custom-data" ]
	[ "${lines[1]}" = "$TEST_HOME/custom-browser" ]
	[ -d "$TEST_HOME/custom-data/.xurl" ]
	[ -d "$TEST_HOME/custom-browser" ]
}

@test "X API up only recreates the current browser and MCP sidecars" {
	run env HERMES_COMPOSE_FILE="$COMPOSE_FILE" bash "$REPO_ROOT/scripts/sh/hermes-xapi.sh" up

	[ "$status" -eq 0 ]
	grep -Fq '<up> <-d> <--force-recreate> <chromium> <browser-mcp> <xapi-mcp>' "$COMMAND_LOG"
	! grep -q '<hermes>\|<hermes-bootstrap>\|<volume>' "$COMMAND_LOG"
}

@test "X API authentication forwards OAuth credentials to the sidecar" {
	run env HERMES_COMPOSE_FILE="$COMPOSE_FILE" bash "$REPO_ROOT/scripts/sh/hermes-xapi.sh" auth

	[ "$status" -eq 0 ]
	grep -Fq '<xapi-mcp>' "$COMMAND_LOG"
	grep -Fq 'xurl auth oauth2 --headless' "$COMMAND_LOG"
	! grep -q 'xapi-client-secret-marker\|service-account-token' "$COMMAND_LOG"
}

@test "uses the Hermes data directory for the default browser directory" {
	export HERMES_DATA_DIR="$TEST_HOME/custom-data"

	run bash -c '
set -euo pipefail
. "$REPO_ROOT/scripts/sh/install-common.sh"
. "$REPO_ROOT/scripts/sh/hermes-sidecar-common.sh"
dotfiles_hermes_browser_data_dir
'

	[ "$status" -eq 0 ]
	[ "$output" = "$TEST_HOME/custom-data/.browser" ]
}

@test "injects X API OAuth credentials from 1Password for explicit wrapper commands" {
	export XAPI_OP_ITEM_JSON='{"id":"xapi-item","fields":[{"label":"X_API_CLIENT_ID","value":"xapi-client-id-marker"},{"label":"X_API_CLIENT_SECRET","value":"xapi-client-secret-marker"}]}'
	printf 'OP_SERVICE_ACCOUNT_TOKEN=cached-token\n' >"$HOME/.hermes/.op.env"
	chmod 600 "$HOME/.hermes/.op.env"

	run bash -c '
set -euo pipefail
. "$REPO_ROOT/scripts/sh/install-common.sh"
. "$REPO_ROOT/scripts/sh/hermes-sidecar-common.sh"
dotfiles_hermes_with_xapi_credentials bash -c '"'"'printf "%s:%s\n" "$X_API_CLIENT_ID" "$X_API_CLIENT_SECRET"'"'"'
'

	[ "$status" -eq 0 ]
	[ "$output" = "xapi-client-id-marker:xapi-client-secret-marker" ]
	grep -q '^op <item> <get> <Hermes X API MCP> <--account> <my.1password.com> <--vault> <openclaw> <--format> <json>$' "$COMMAND_LOG"
	! grep -q 'xapi-client-secret-marker' "$COMMAND_LOG"
}

@test "initializes the service account cache for a standalone X API command" {
	run bash -c '
set -euo pipefail
. "$REPO_ROOT/scripts/sh/install-common.sh"
. "$REPO_ROOT/scripts/sh/hermes-sidecar-common.sh"
dotfiles_hermes_with_xapi_credentials bash -c '"'"'printf "%s:%s\n" "$X_API_CLIENT_ID" "$X_API_CLIENT_SECRET"'"'"'
'

	[ "$status" -eq 0 ]
	[ "$output" = "xapi-client-id-marker:xapi-client-secret-marker" ]
	grep -q '<read>' "$COMMAND_LOG"
	! grep -q '<signin>' "$COMMAND_LOG"
	grep -q '^op <item> <get> <Hermes X API MCP> ' "$COMMAND_LOG"
	[ "$(cat "$HOME/.hermes/.op.env")" = 'OP_SERVICE_ACCOUNT_TOKEN=service-account-token' ]
	[ "$(service_account_cache_mode)" = 600 ]
}

@test "uses a valid service account cache without a trailing newline" {
	printf 'OP_SERVICE_ACCOUNT_TOKEN=cached-token' >"$HOME/.hermes/.op.env"
	chmod 600 "$HOME/.hermes/.op.env"

	run bash -c '
set -euo pipefail
. "$REPO_ROOT/scripts/sh/install-common.sh"
. "$REPO_ROOT/scripts/sh/hermes-sidecar-common.sh"
dotfiles_hermes_with_xapi_credentials bash -c '"'"'printf "%s:%s\n" "$X_API_CLIENT_ID" "$X_API_CLIENT_SECRET"'"'"'
'

	[ "$status" -eq 0 ]
	[ "$output" = "xapi-client-id-marker:xapi-client-secret-marker" ]
	run grep -q '<read>' "$COMMAND_LOG"
	[ "$status" -eq 1 ]
	[ "$(cat "$OP_TOKEN_CAPTURE")" = cached-token ]
}

@test "syncs the X API refresh token into the local xurl cache before startup" {
	local xapi_lookup_count last_xapi_lookup up_line
	run_restart_sidecar

	[ "$status" -eq 0 ]
	[ "$(stat -c '%a' "$HOME/.hermes/.xurl/auth.yml" 2>/dev/null || stat -f '%Lp' "$HOME/.hermes/.xurl/auth.yml")" = 600 ]
	grep -q 'client_id: "xapi-client-id-marker"' "$HOME/.hermes/.xurl/auth.yml"
	grep -q 'client_secret: "xapi-client-secret-marker"' "$HOME/.hermes/.xurl/auth.yml"
	grep -q 'refresh_token: "xapi-refresh-token-marker"' "$HOME/.hermes/.xurl/auth.yml"
	xapi_lookup_count="$(grep -c '<Hermes X API MCP>' "$COMMAND_LOG")"
	[ "$xapi_lookup_count" -ge 2 ]
	last_xapi_lookup="$(grep -n '<Hermes X API MCP>' "$COMMAND_LOG" | tail -n 1 | cut -d: -f1)"
	up_line="$(grep -n '<up> <-d> <--force-recreate> <xapi-mcp>' "$COMMAND_LOG" | cut -d: -f1)"
	[ "$last_xapi_lookup" -lt "$up_line" ]
	! grep -q 'xapi-refresh-token-marker' "$COMMAND_LOG"
	! grep -q '<item> <edit>' "$COMMAND_LOG"
}

@test "validates the X API token before recreating the X API sidecars" {
	local probe_line up_line

	run_restart_sidecar

	[ "$status" -eq 0 ]
	[ "$(cat "$XAPI_TOKEN_ATTEMPT_FILE")" -eq 1 ]
	probe_line="$(grep -n '<run> <--rm> <--no-deps> <--entrypoint> </bin/sh> <xapi-mcp>' "$COMMAND_LOG" | tail -n 1 | cut -d: -f1)"
	up_line="$(grep -n '<up> <-d> <--force-recreate> <xapi-mcp>' "$COMMAND_LOG" | cut -d: -f1)"
	[ -n "$probe_line" ]
	[ "$probe_line" -lt "$up_line" ]
}

@test "replaces an invalid local X API token from 1Password and validates it once" {
	mkdir -p "$HOME/.hermes/.xurl"
	cat >"$HOME/.hermes/.xurl/auth.yml" <<'EOF'
apps:
  default:
    client_id: "stale-client-id"
    client_secret: "stale-client-secret"
    oauth2_tokens:
      default:
        type: oauth2
        oauth2:
          refresh_token: "stale-refresh-token"
default_app: default
EOF
	chmod 600 "$HOME/.hermes/.xurl/auth.yml"
	export XAPI_TOKEN_READY_AFTER=2

	run_restart_sidecar

	[ "$status" -eq 0 ]
	[ "$(cat "$XAPI_TOKEN_ATTEMPT_FILE")" -eq 2 ]
	grep -q 'client_id: "xapi-client-id-marker"' "$HOME/.hermes/.xurl/auth.yml"
	grep -q 'client_secret: "xapi-client-secret-marker"' "$HOME/.hermes/.xurl/auth.yml"
	grep -q 'refresh_token: "xapi-refresh-token-marker"' "$HOME/.hermes/.xurl/auth.yml"
	grep -q '<up> <-d> <--force-recreate>' "$COMMAND_LOG"
	! grep -q 'stale-refresh-token' "$COMMAND_LOG"
}

@test "stops before sidecar recreation when local and 1Password X API tokens are invalid" {
	mkdir -p "$HOME/.hermes/.xurl"
	cat >"$HOME/.hermes/.xurl/auth.yml" <<'EOF'
apps:
  default:
    oauth2_tokens:
      default:
        type: oauth2
        oauth2:
          refresh_token: "stale-refresh-token"
default_app: default
EOF
	chmod 600 "$HOME/.hermes/.xurl/auth.yml"
	export XAPI_TOKEN_READY_AFTER=99

	run_restart_sidecar

	[ "$status" -ne 0 ]
	[ "$(cat "$XAPI_TOKEN_ATTEMPT_FILE")" -eq 2 ]
	[[ "$output" == *"task hermes:xapi:setup"* ]]
	grep -q 'refresh_token: "stale-refresh-token"' "$HOME/.hermes/.xurl/auth.yml"
	! grep -q '<up> <-d> <--force-recreate>' "$COMMAND_LOG"
	! grep -q 'stale-refresh-token' "$COMMAND_LOG"
}

@test "does not replace the local X API cache after a Docker probe failure" {
	mkdir -p "$HOME/.hermes/.xurl"
	cat >"$HOME/.hermes/.xurl/auth.yml" <<'EOF'
apps:
  default:
    oauth2_tokens:
      default:
        type: oauth2
        oauth2:
          refresh_token: "local-refresh-token"
default_app: default
EOF
	chmod 600 "$HOME/.hermes/.xurl/auth.yml"
	export XAPI_TOKEN_READY_AFTER=99
	export XAPI_TOKEN_FAILURE_KIND=infrastructure
	export XAPI_TOKEN_FAILURE_STATUS=125

	run_restart_sidecar

	[ "$status" -eq 125 ]
	[ "$(cat "$XAPI_TOKEN_ATTEMPT_FILE")" -eq 1 ]
	grep -q 'refresh_token: "local-refresh-token"' "$HOME/.hermes/.xurl/auth.yml"
	[[ "$output" != *"task hermes:xapi:setup"* ]]
	! grep -q '<item> <edit>' "$COMMAND_LOG"
	! grep -q '<up> <-d> <--force-recreate>' "$COMMAND_LOG"
}

@test "syncs a refresh token rotated by a successful X API probe back to 1Password" {
	mkdir -p "$HOME/.hermes/.xurl"
	cat >"$HOME/.hermes/.xurl/auth.yml" <<'EOF'
apps:
  default:
    oauth2_tokens:
      default:
        type: oauth2
        oauth2:
          refresh_token: "local-refresh-token"
default_app: default
EOF
	chmod 600 "$HOME/.hermes/.xurl/auth.yml"
	export XAPI_ROTATED_REFRESH_TOKEN=rotated-refresh-token

	run_restart_sidecar

	[ "$status" -eq 0 ]
	jq -e '.fields[] | select(.label == "X_API_REFRESH_TOKEN") | .value == "rotated-refresh-token"' "$EDIT_CAPTURE" >/dev/null
	! grep -q 'rotated-refresh-token' "$COMMAND_LOG"
}

@test "keeps a successfully rotated local X API token when 1Password sync fails" {
	mkdir -p "$HOME/.hermes/.xurl"
	cat >"$HOME/.hermes/.xurl/auth.yml" <<'EOF'
apps:
  default:
    oauth2_tokens:
      default:
        type: oauth2
        oauth2:
          refresh_token: "local-refresh-token"
default_app: default
EOF
	chmod 600 "$HOME/.hermes/.xurl/auth.yml"
	export XAPI_ROTATED_REFRESH_TOKEN=rotated-refresh-token
	export OP_EDIT_STATUS=17

	run_restart_sidecar

	[ "$status" -eq 17 ]
	grep -q 'refresh_token: "rotated-refresh-token"' "$HOME/.hermes/.xurl/auth.yml"
	! grep -q 'refresh_token: "local-refresh-token"' "$HOME/.hermes/.xurl/auth.yml"
	! grep -q '<up> <-d> <--force-recreate>' "$COMMAND_LOG"
}

@test "sync-token writes the local refresh token through the 1Password template" {
	mkdir -p "$HOME/.hermes/.xurl"
	cat >"$HOME/.hermes/.xurl/auth.yml" <<'EOF'
apps:
    default:
        oauth2_tokens:
            app-user:
                oauth2:
                    refresh_token: local-refresh-token-marker
default_app: default
EOF
	chmod 600 "$HOME/.hermes/.xurl/auth.yml"

	run env HERMES_COMPOSE_FILE="$REPO_ROOT/docker/hermes-service/compose.yml" \
		bash "$REPO_ROOT/scripts/sh/hermes-xapi.sh" sync-token

	[ "$status" -eq 0 ]
	jq -e '.fields[] | select(.label == "X_API_REFRESH_TOKEN") | .value == "local-refresh-token-marker"' "$EDIT_CAPTURE" >/dev/null
	grep -q '<read>' "$COMMAND_LOG"
	! grep -q '<signin>' "$COMMAND_LOG"
	[ "$(cat "$HOME/.hermes/.op.env")" = 'OP_SERVICE_ACCOUNT_TOKEN=service-account-token' ]
	[ "$(cat "$OP_TOKEN_CAPTURE")" = 'service-account-token' ]
	! grep -q 'local-refresh-token-marker' "$COMMAND_LOG"
}

@test "sync-token updates the configured OAuth item" {
	export DOTFILES_HERMES_XAPI_OAUTH_ITEM='Hermes X API MCP OAuth'
	export XAPI_OAUTH_ITEM_JSON='{"id":"xapi-oauth-item","fields":[{"label":"X_API_REFRESH_TOKEN","section":{"label":"Refresh Token"},"value":"xapi-refresh-token-marker"}]}'
	mkdir -p "$HOME/.hermes/.xurl"
	cat >"$HOME/.hermes/.xurl/auth.yml" <<'EOF'
apps:
    default:
        oauth2_tokens:
            app-user:
                oauth2:
                    refresh_token: configured-item-refresh-token-marker
default_app: default
EOF
	chmod 600 "$HOME/.hermes/.xurl/auth.yml"

	run env HERMES_COMPOSE_FILE="$REPO_ROOT/docker/hermes-service/compose.yml" \
		bash "$REPO_ROOT/scripts/sh/hermes-xapi.sh" sync-token

	[ "$status" -eq 0 ]
	grep -q '<item> <get> <Hermes X API MCP OAuth>' "$COMMAND_LOG"
	grep -q '<item> <edit> <Hermes X API MCP OAuth>' "$COMMAND_LOG"
	jq -e '.fields[] | select(.label == "X_API_REFRESH_TOKEN") | .value == "configured-item-refresh-token-marker"' "$EDIT_CAPTURE" >/dev/null
}

@test "uses a mode-0600 cached service account without starting an op read" {
	printf 'OP_SERVICE_ACCOUNT_TOKEN=cached-token\n' >"$HOME/.hermes/.op.env"
	chmod 600 "$HOME/.hermes/.op.env"
	export OP_READ_COMPLETION_FILE="$BATS_TEST_TMPDIR/op-read-completed"
	export OP_READ_DELAY_SECONDS=2 DOTFILES_HERMES_OP_READ_TIMEOUT_SECONDS=1
	run_restart_sidecar
	[ "$status" -eq 0 ]
	[[ "$output" != *"using existing Hermes service-account environment"* ]]
	run grep -q '<read>' "$COMMAND_LOG"
	[ "$status" -eq 1 ]
	[ "$(cat "$HOME/.hermes/.op.env")" = 'OP_SERVICE_ACCOUNT_TOKEN=cached-token' ]
	[ "$(service_account_cache_mode)" = 600 ]
	/bin/sleep 2
	[ ! -e "$OP_READ_COMPLETION_FILE" ]
	[ "$(cat "$HOME/.hermes/.op.env")" = 'OP_SERVICE_ACCOUNT_TOKEN=cached-token' ]
	[ "$(service_account_cache_mode)" = 600 ]
}

@test "uses a valid cached service account for every host item read without desktop authorization" {
	local bootstrap_output
	printf 'OP_SERVICE_ACCOUNT_TOKEN=cached-token\n' >"$HOME/.hermes/.op.env"
	chmod 600 "$HOME/.hermes/.op.env"
	export OP_READ_TOKEN='unexpected-refresh-token'

	run_restart_sidecar

	[ "$status" -eq 0 ]
	bootstrap_output="$output"
	run grep -q '<read>' "$COMMAND_LOG"
	[ "$status" -eq 1 ]
	run grep -q '<signin>' "$COMMAND_LOG"
	[ "$status" -eq 1 ]
	[ -s "$OP_TOKEN_CAPTURE" ]
	run grep -vx 'cached-token' "$OP_TOKEN_CAPTURE"
	[ "$status" -eq 1 ]
	[[ "$bootstrap_output" != *'cached-token'* ]]
}

@test "rejects a writable cached service account after an op read timeout" {
	printf 'OP_SERVICE_ACCOUNT_TOKEN=cached-token\n' >"$HOME/.hermes/.op.env"
	chmod 644 "$HOME/.hermes/.op.env"
	export OP_READ_DELAY_SECONDS=2 DOTFILES_HERMES_OP_READ_TIMEOUT_SECONDS=1
	run_restart_sidecar
	[ "$status" -ne 0 ]
	! grep -q '^op' "$COMMAND_LOG"
	! grep -q '<compose>' "$COMMAND_LOG"
}

@test "rejects a symlinked cached service account before Compose" {
	printf 'OP_SERVICE_ACCOUNT_TOKEN=cached-token\n' >"$HOME/.hermes/cache-target"
	chmod 600 "$HOME/.hermes/cache-target"
	ln -s "$HOME/.hermes/cache-target" "$HOME/.hermes/.op.env"
	assert_service_account_cache_rejected_after_timeout
}

@test "rejects a directory cached service account before Compose" {
	mkdir "$HOME/.hermes/.op.env"
	assert_service_account_cache_rejected_after_timeout
}

@test "rejects an empty cached service account token after an op read timeout" {
	printf 'OP_SERVICE_ACCOUNT_TOKEN=\n' >"$HOME/.hermes/.op.env"
	chmod 600 "$HOME/.hermes/.op.env"
	assert_service_account_cache_rejected_after_timeout
}

@test "rejects an extra cached service account line after an op read timeout" {
	printf 'OP_SERVICE_ACCOUNT_TOKEN=cached-token\nOP_SERVICE_ACCOUNT_TOKEN=extra-token\n' >"$HOME/.hermes/.op.env"
	chmod 600 "$HOME/.hermes/.op.env"
	assert_service_account_cache_rejected_after_timeout
}

@test "rejects a malformed cached service account line after an op read timeout" {
	printf 'OP_SERVICE_ACCOUNT_TOKEN=cached-token\nnot-an-environment-assignment\n' >"$HOME/.hermes/.op.env"
	chmod 600 "$HOME/.hermes/.op.env"
	assert_service_account_cache_rejected_after_timeout
}

@test "defaults invalid service-account read timeouts to twenty seconds" {
	grep -Fq 'timeout_seconds="${DOTFILES_HERMES_OP_READ_TIMEOUT_SECONDS:-20}"' "$REPO_ROOT/scripts/sh/hermes-sidecar-common.sh"
	grep -Fq '[[ $timeout_seconds =~ ^([1-9]|[1-9][0-9]|[12][0-9]{2}|300)$ ]] || timeout_seconds=20' "$REPO_ROOT/scripts/sh/hermes-sidecar-common.sh"
	export DOTFILES_HERMES_OP_READ_TIMEOUT_SECONDS=invalid
	run_restart_sidecar
	[ "$status" -eq 0 ]
}

@test "defaults service-account read timeouts above 300 seconds to twenty seconds" {
	grep -Fq '[[ $timeout_seconds =~ ^([1-9]|[1-9][0-9]|[12][0-9]{2}|300)$ ]] || timeout_seconds=20' "$REPO_ROOT/scripts/sh/hermes-sidecar-common.sh"
	export DOTFILES_HERMES_OP_READ_TIMEOUT_SECONDS=301
	run_restart_sidecar
	[ "$status" -eq 0 ]
}

@test "defaults arbitrarily large service-account read timeouts to twenty seconds" {
	export DOTFILES_HERMES_OP_READ_TIMEOUT_SECONDS=999999999999999999999999999999999999
	run bash -c '
set -euo pipefail
. "$REPO_ROOT/scripts/sh/install-common.sh"
. "$REPO_ROOT/scripts/sh/hermes-sidecar-common.sh"
dotfiles_hermes_service_account_read_timeout_seconds
'
	[ "$status" -eq 0 ]
	[ "$output" = 20 ]
}

@test "atomically replaces an old service account cache after a successful op read" {
	printf 'OP_SERVICE_ACCOUNT_TOKEN=old-token\n' >"$HOME/.hermes/.op.env"
	chmod 600 "$HOME/.hermes/.op.env"
	ln "$HOME/.hermes/.op.env" "$HOME/.hermes/.op.env.previous"
	export OP_READ_TOKEN='fresh-token'
	export DOTFILES_HERMES_REFRESH_SERVICE_ACCOUNT=1
	run_restart_sidecar
	[ "$status" -eq 0 ]
	[ "$(cat "$HOME/.hermes/.op.env")" = 'OP_SERVICE_ACCOUNT_TOKEN=fresh-token' ]
	[ "$(service_account_cache_mode)" = 600 ]
	[ "$(cat "$HOME/.hermes/.op.env.previous")" = 'OP_SERVICE_ACCOUNT_TOKEN=old-token' ]
	[ "$(service_account_cache_inode "$HOME/.hermes/.op.env")" != "$(service_account_cache_inode "$HOME/.hermes/.op.env.previous")" ]
	[ -z "$(find "$HOME/.hermes" -maxdepth 1 -name '.op.env.*' ! -name '.op.env.previous' -print -quit)" ]
}

@test "preserves the old service account cache when fresh replacement cannot be staged" {
	printf 'OP_SERVICE_ACCOUNT_TOKEN=old-token\n' >"$HOME/.hermes/.op.env"
	chmod 600 "$HOME/.hermes/.op.env"
	write_stub mktemp '
case "${1:-}" in
  *.op.read.XXXXXX) exec /usr/bin/mktemp "$@" ;;
  *) exit 1 ;;
esac
'
	export OP_READ_TOKEN='fresh-token'
	export DOTFILES_HERMES_REFRESH_SERVICE_ACCOUNT=1
	run_restart_sidecar
	status=$status
	output=$output
	[ "$status" -ne 0 ]
	! grep -q '<compose>' "$COMMAND_LOG"
	[ "$(cat "$HOME/.hermes/.op.env")" = 'OP_SERVICE_ACCOUNT_TOKEN=old-token' ]
	[ "$(service_account_cache_mode)" = 600 ]
}

@test "fails preflight before Compose when op is unavailable" {
	run_restart_sidecar op

	[ "$status" -ne 0 ]
	[[ "$output" == *"1Password CLI (op) is required"* ]]
	[ ! -s "$COMMAND_LOG" ]
}

@test "fails preflight before Compose when jq is unavailable" {
	run_restart_sidecar jq

	[ "$status" -ne 0 ]
	[[ "$output" == *"jq is required"* ]]
	[ ! -s "$COMMAND_LOG" ]
}

@test "fails preflight before Compose when python3 is unavailable" {
	run_restart_sidecar python3

	[ "$status" -ne 0 ]
	[[ "$output" == *"python3 is required"* ]]
	[ ! -s "$COMMAND_LOG" ]
}
