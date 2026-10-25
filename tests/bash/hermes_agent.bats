#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	TEST_HOME="$BATS_TEST_TMPDIR/home"
	STUB_BIN="$BATS_TEST_TMPDIR/bin"
	COMMAND_LOG="$BATS_TEST_TMPDIR/commands.log"
	EDIT_CAPTURE="$BATS_TEST_TMPDIR/item-edit.json"
	OP_TOKEN_CAPTURE="$BATS_TEST_TMPDIR/op-token.log"
	XAPI_TOKEN_ATTEMPT_FILE="$BATS_TEST_TMPDIR/xapi-token-attempts"
	REAL_JQ="$(command -v jq)"
	REAL_YQ="$(command -v yq)"
	REAL_SLEEP="$(command -v sleep)"
	REAL_MKTEMP="$(command -v mktemp)"
	mkdir -p "$TEST_HOME/.hermes" "$STUB_BIN"
	: >"$COMMAND_LOG"
	: >"$OP_TOKEN_CAPTURE"
	printf '0\n' >"$XAPI_TOKEN_ATTEMPT_FILE"

	export REPO_ROOT PATH="$STUB_BIN:$PATH"
	isolate_hermes_test_environment
	unset DOTFILES_USER SUDO_USER
	unset OP_SERVICE_ACCOUNT_TOKEN
	export COMMAND_LOG EDIT_CAPTURE OP_TOKEN_CAPTURE XAPI_TOKEN_ATTEMPT_FILE REAL_JQ REAL_YQ REAL_SLEEP REAL_MKTEMP
	export OP_ITEM_JSON='{"id":"item-id","fields":[{"label":"credential","value":"adapter-secret-marker"}]}'
	export XAPI_OP_ITEM_JSON='{"id":"xapi-item","fields":[{"label":"X_API_CLIENT_ID","value":"xapi-client-id-marker"},{"label":"X_API_CLIENT_SECRET","value":"xapi-client-secret-marker"},{"label":"X_API_REFRESH_TOKEN","section":{"label":"Refresh Token"},"value":"xapi-refresh-token-marker"}]}'
	export XAPI_OAUTH_ITEM_JSON='{"id":"xapi-oauth-item","fields":[{"label":"X_API_REFRESH_TOKEN","value":"xapi-refresh-token-marker"}]}'
	export OP_FAIL_ITEM=""
	export OP_EDIT_STATUS=0
	export OP_DELAY_SECONDS=0
	export OP_READ_TOKEN='service-account-token'
	export OP_READ_DELAY_SECONDS=0
	export OP_READ_COMPLETION_FILE=""
	export XAPI_TOKEN_READY_AFTER=1
	export XAPI_TOKEN_FAILURE_KIND=auth
	export XAPI_TOKEN_FAILURE_STATUS=1
	export XAPI_ROTATED_REFRESH_TOKEN=""

	write_stub jq '
exec "$REAL_JQ" "$@"
'
	write_stub yq '
exec "$REAL_YQ" "$@"
'
	write_stub op '
printf "op" >>"$COMMAND_LOG"
printf " <%s>" "$@" >>"$COMMAND_LOG"
printf "\n" >>"$COMMAND_LOG"
	case "${3:-}" in
	read)
		if [[ ${OP_READ_DELAY_SECONDS:-0} != 0 ]]; then
			"$REAL_SLEEP" "$OP_READ_DELAY_SECONDS"
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
			"$REAL_SLEEP" "$OP_DELAY_SECONDS"
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
	write_stub xurl '
printf "xurl" >>"$COMMAND_LOG"
printf " <%s>" "$@" >>"$COMMAND_LOG"
printf "\n" >>"$COMMAND_LOG"
[[ ${CLIENT_ID:-} == xapi-client-id-marker ]] || exit 64
[[ ${CLIENT_SECRET:-} == xapi-client-secret-marker ]] || exit 64
case "${1:-}" in
  token)
	attempt="$(cat "$XAPI_TOKEN_ATTEMPT_FILE")"
	attempt=$((attempt + 1))
	printf "%s\n" "$attempt" >"$XAPI_TOKEN_ATTEMPT_FILE"
	if ((attempt < XAPI_TOKEN_READY_AFTER)); then
		if [[ $XAPI_TOKEN_FAILURE_KIND == auth ]]; then
			printf "%s\n" "Error: no valid oauth2 token for app default: Auth Error: TokenNotFound (cause: oauth2 token not found)" >&2
			printf "%s\n" "Run: xurl auth oauth2" >&2
		else
			printf "%s\n" "Could not connect to the X API token endpoint." >&2
		fi
		exit "$XAPI_TOKEN_FAILURE_STATUS"
	fi
	if [[ -n ${XAPI_ROTATED_REFRESH_TOKEN:-} ]]; then
		sed -i.bak "s/refresh_token:.*/refresh_token: \"$XAPI_ROTATED_REFRESH_TOKEN\"/" "$HERMES_DATA_DIR/.xurl/auth.yml"
		rm -f "$HERMES_DATA_DIR/.xurl/auth.yml.bak"
	fi
	printf "%s\n" "xapi-access-token-marker"
	;;
  auth)
	[[ $* == "auth oauth2 --headless" ]] || exit 64
	;;
  mcp)
	[[ $# == 2 && $2 == https://api.x.com/mcp ]] || exit 64
	;;
  *)
	exit 64
	;;
esac
'
	write_stub timeout '
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

isolate_hermes_test_environment() {
	export HOME="$TEST_HOME"
	export HERMES_DATA_DIR="$TEST_HOME/.hermes"
	unset HERMES_HOME USERPROFILE DOTFILES_HERMES_OP_EXECUTABLE
	unset CLIENT_ID CLIENT_SECRET X_API_CLIENT_ID X_API_CLIENT_SECRET
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

run_xapi_mcp() {
	local missing_command="${1:-}"
	if [[ -z $missing_command ]]; then
		run bash "$REPO_ROOT/scripts/sh/hermes-xapi.sh" mcp
		return
	fi
	run env DOTFILES_TEST_MISSING_COMMAND="$missing_command" bash -c '
set -euo pipefail
. "$REPO_ROOT/scripts/sh/install-common.sh"
. "$REPO_ROOT/scripts/sh/hermes-xapi-common.sh"
if [[ -n ${DOTFILES_TEST_MISSING_COMMAND:-} ]]; then
  dotfiles_have() {
    [[ $1 != "$DOTFILES_TEST_MISSING_COMMAND" ]] && command -v "$1" >/dev/null 2>&1
  }
fi
dotfiles_hermes_require_xapi_tools
dotfiles_hermes_prepare_runtime_home
dotfiles_hermes_ensure_xapi_auth
dotfiles_hermes_with_xapi_credentials xurl mcp https://api.x.com/mcp
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
	run_xapi_mcp
	[ "$status" -ne 0 ]
	! grep -q '^xurl ' "$COMMAND_LOG"
}

@test "uses the explicit Hermes data directory before HERMES_HOME and USERPROFILE" {
	export HERMES_DATA_DIR="$TEST_HOME/custom-data"
	export HERMES_HOME="$TEST_HOME/profile-home"
	export USERPROFILE="$TEST_HOME/windows-profile"

	run bash -c '
set -euo pipefail
. "$REPO_ROOT/scripts/sh/install-common.sh"
. "$REPO_ROOT/scripts/sh/hermes-xapi-common.sh"
dotfiles_hermes_data_dir
dotfiles_hermes_prepare_runtime_home
'

	[ "$status" -eq 0 ]
	[ "$output" = "$TEST_HOME/custom-data" ]
	[ -d "$TEST_HOME/custom-data/.xurl" ]
	[ -f "$TEST_HOME/custom-data/.op.env" ]
	[ ! -e "$TEST_HOME/profile-home" ]
	[ ! -e "$TEST_HOME/windows-profile" ]
}

@test "Hermes test setup isolates inherited host paths and the 1Password executable" {
	local inherited_root="$BATS_TEST_TMPDIR/inherited"
	mkdir -p "$inherited_root"
	cat >"$inherited_root/op" <<'EOF'
#!/usr/bin/env bash
printf 'called\n' >"$(dirname "$0")/op-called"
exit 97
EOF
	chmod +x "$inherited_root/op"
	export HOME="$inherited_root/home" USERPROFILE="$inherited_root/profile"
	export HERMES_DATA_DIR="$inherited_root/data"
	export HERMES_HOME="$inherited_root/profile-home"
	export DOTFILES_HERMES_OP_EXECUTABLE="$inherited_root/op"

	isolate_hermes_test_environment
	run_xapi_mcp

	[ "$status" -eq 0 ]
	[ "$HOME" = "$TEST_HOME" ]
	[ -z "${USERPROFILE+x}" ]
	[ ! -e "$inherited_root/op-called" ]
	[ ! -e "$inherited_root/home" ]
	[ ! -e "$inherited_root/profile" ]
	[ ! -e "$inherited_root/data" ]
	[ ! -e "$inherited_root/profile-home" ]
	[ -f "$TEST_HOME/.hermes/.op.env" ]
	[ -f "$TEST_HOME/.hermes/.xurl/auth.yml" ]
}

@test "X API MCP starts the native xurl bridge with OAuth credentials" {
	run_xapi_mcp

	[ "$status" -eq 0 ]
	grep -Fq 'xurl <mcp> <https://api.x.com/mcp>' "$COMMAND_LOG"
	! grep -q 'xapi-client-secret-marker\|service-account-token' "$COMMAND_LOG"
}

@test "X API authentication forwards OAuth credentials to native xurl" {
	run bash "$REPO_ROOT/scripts/sh/hermes-xapi.sh" auth

	[ "$status" -eq 0 ]
	grep -Fq 'xurl <auth> <oauth2> <--headless>' "$COMMAND_LOG"
	! grep -q 'xapi-client-secret-marker\|service-account-token' "$COMMAND_LOG"
}

@test "uses HERMES_HOME then HOME for native xurl state while ignoring USERPROFILE" {
	unset HERMES_DATA_DIR
	export HERMES_HOME="$TEST_HOME/profile-home"
	export USERPROFILE="$TEST_HOME/windows-profile"

	run bash -c '
set -euo pipefail
. "$REPO_ROOT/scripts/sh/install-common.sh"
. "$REPO_ROOT/scripts/sh/hermes-xapi-common.sh"
dotfiles_hermes_data_dir
unset HERMES_HOME
dotfiles_hermes_data_dir
'

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "$TEST_HOME/profile-home" ]
	[ "${lines[1]}" = "$TEST_HOME/.hermes" ]
}

@test "injects X API OAuth credentials from 1Password for explicit wrapper commands" {
	export XAPI_OP_ITEM_JSON='{"id":"xapi-item","fields":[{"label":"X_API_CLIENT_ID","value":"xapi-client-id-marker"},{"label":"X_API_CLIENT_SECRET","value":"xapi-client-secret-marker"}]}'
	printf 'OP_SERVICE_ACCOUNT_TOKEN=cached-token\n' >"$HOME/.hermes/.op.env"
	chmod 600 "$HOME/.hermes/.op.env"

	run bash -c '
set -euo pipefail
. "$REPO_ROOT/scripts/sh/install-common.sh"
. "$REPO_ROOT/scripts/sh/hermes-xapi-common.sh"
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
. "$REPO_ROOT/scripts/sh/hermes-xapi-common.sh"
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
. "$REPO_ROOT/scripts/sh/hermes-xapi-common.sh"
dotfiles_hermes_with_xapi_credentials bash -c '"'"'printf "%s:%s\n" "$X_API_CLIENT_ID" "$X_API_CLIENT_SECRET"'"'"'
'

	[ "$status" -eq 0 ]
	[ "$output" = "xapi-client-id-marker:xapi-client-secret-marker" ]
	run grep -q '<read>' "$COMMAND_LOG"
	[ "$status" -eq 1 ]
	[ "$(cat "$OP_TOKEN_CAPTURE")" = cached-token ]
}

@test "syncs the X API refresh token into the local xurl cache before MCP startup" {
	local xapi_lookup_count last_xapi_lookup mcp_line
	run_xapi_mcp

	[ "$status" -eq 0 ]
	[ "$(stat -c '%a' "$HOME/.hermes/.xurl/auth.yml" 2>/dev/null || stat -f '%Lp' "$HOME/.hermes/.xurl/auth.yml")" = 600 ]
	grep -q 'client_id: "xapi-client-id-marker"' "$HOME/.hermes/.xurl/auth.yml"
	grep -q 'client_secret: "xapi-client-secret-marker"' "$HOME/.hermes/.xurl/auth.yml"
	grep -q 'refresh_token: "xapi-refresh-token-marker"' "$HOME/.hermes/.xurl/auth.yml"
	xapi_lookup_count="$(grep -c '<Hermes X API MCP>' "$COMMAND_LOG")"
	[ "$xapi_lookup_count" -ge 2 ]
	last_xapi_lookup="$(grep -n '<Hermes X API MCP>' "$COMMAND_LOG" | tail -n 1 | cut -d: -f1)"
	mcp_line="$(grep -n '^xurl <mcp> <https://api.x.com/mcp>$' "$COMMAND_LOG" | cut -d: -f1)"
	[ "$last_xapi_lookup" -lt "$mcp_line" ]
	! grep -q 'xapi-refresh-token-marker' "$COMMAND_LOG"
	! grep -q '<item> <edit>' "$COMMAND_LOG"
}

@test "validates the X API token before starting MCP without exposing its stdout" {
	local probe_line mcp_line

	run_xapi_mcp

	[ "$status" -eq 0 ]
	[ "$(cat "$XAPI_TOKEN_ATTEMPT_FILE")" -eq 1 ]
	probe_line="$(grep -n '^xurl <token>$' "$COMMAND_LOG" | tail -n 1 | cut -d: -f1)"
	mcp_line="$(grep -n '^xurl <mcp> <https://api.x.com/mcp>$' "$COMMAND_LOG" | cut -d: -f1)"
	[ -n "$probe_line" ]
	[ "$probe_line" -lt "$mcp_line" ]
	[[ "$output" != *"xapi-access-token-marker"* ]]
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

	run_xapi_mcp

	[ "$status" -eq 0 ]
	[ "$(cat "$XAPI_TOKEN_ATTEMPT_FILE")" -eq 2 ]
	grep -q 'client_id: "xapi-client-id-marker"' "$HOME/.hermes/.xurl/auth.yml"
	grep -q 'client_secret: "xapi-client-secret-marker"' "$HOME/.hermes/.xurl/auth.yml"
	grep -q 'refresh_token: "xapi-refresh-token-marker"' "$HOME/.hermes/.xurl/auth.yml"
	grep -q '^xurl <mcp>' "$COMMAND_LOG"
	! grep -q 'stale-refresh-token' "$COMMAND_LOG"
}

@test "stops before MCP startup when local and 1Password X API tokens are invalid" {
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

	run_xapi_mcp

	[ "$status" -ne 0 ]
	[ "$(cat "$XAPI_TOKEN_ATTEMPT_FILE")" -eq 2 ]
	[[ "$output" == *"task hermes:xapi:setup"* ]]
	grep -q 'refresh_token: "stale-refresh-token"' "$HOME/.hermes/.xurl/auth.yml"
	! grep -q '^xurl <mcp>' "$COMMAND_LOG"
	! grep -q 'stale-refresh-token' "$COMMAND_LOG"
}

@test "does not replace the local X API cache after a native xurl connection failure" {
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

	run_xapi_mcp

	[ "$status" -eq 125 ]
	[ "$(cat "$XAPI_TOKEN_ATTEMPT_FILE")" -eq 1 ]
	grep -q 'refresh_token: "local-refresh-token"' "$HOME/.hermes/.xurl/auth.yml"
	[[ "$output" != *"task hermes:xapi:setup"* ]]
	! grep -q '<item> <edit>' "$COMMAND_LOG"
	! grep -q '^xurl <mcp>' "$COMMAND_LOG"
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

	run_xapi_mcp

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

	run_xapi_mcp

	[ "$status" -eq 17 ]
	grep -q 'refresh_token: "rotated-refresh-token"' "$HOME/.hermes/.xurl/auth.yml"
	! grep -q 'refresh_token: "local-refresh-token"' "$HOME/.hermes/.xurl/auth.yml"
	! grep -q '^xurl <mcp>' "$COMMAND_LOG"
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

	run bash "$REPO_ROOT/scripts/sh/hermes-xapi.sh" sync-token

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

	run bash "$REPO_ROOT/scripts/sh/hermes-xapi.sh" sync-token

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
	run_xapi_mcp
	[ "$status" -eq 0 ]
	[[ "$output" != *"using existing Hermes service-account environment"* ]]
	run grep -q '<read>' "$COMMAND_LOG"
	[ "$status" -eq 1 ]
	[ "$(cat "$HOME/.hermes/.op.env")" = 'OP_SERVICE_ACCOUNT_TOKEN=cached-token' ]
	[ "$(service_account_cache_mode)" = 600 ]
	"$REAL_SLEEP" 2
	[ ! -e "$OP_READ_COMPLETION_FILE" ]
	[ "$(cat "$HOME/.hermes/.op.env")" = 'OP_SERVICE_ACCOUNT_TOKEN=cached-token' ]
	[ "$(service_account_cache_mode)" = 600 ]
}

@test "uses a valid cached service account for every host item read without desktop authorization" {
	local bootstrap_output
	printf 'OP_SERVICE_ACCOUNT_TOKEN=cached-token\n' >"$HOME/.hermes/.op.env"
	chmod 600 "$HOME/.hermes/.op.env"
	export OP_READ_TOKEN='unexpected-refresh-token'

	run_xapi_mcp

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
	run_xapi_mcp
	[ "$status" -ne 0 ]
	! grep -q '^op' "$COMMAND_LOG"
	! grep -q '^xurl ' "$COMMAND_LOG"
}

@test "rejects a symlinked cached service account before native xurl" {
	printf 'OP_SERVICE_ACCOUNT_TOKEN=cached-token\n' >"$HOME/.hermes/cache-target"
	chmod 600 "$HOME/.hermes/cache-target"
	ln -s "$HOME/.hermes/cache-target" "$HOME/.hermes/.op.env"
	assert_service_account_cache_rejected_after_timeout
}

@test "rejects a directory cached service account before native xurl" {
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

@test "defaults arbitrarily large service-account read timeouts to twenty seconds" {
	export DOTFILES_HERMES_OP_READ_TIMEOUT_SECONDS=999999999999999999999999999999999999
	run bash -c '
set -euo pipefail
. "$REPO_ROOT/scripts/sh/install-common.sh"
. "$REPO_ROOT/scripts/sh/hermes-xapi-common.sh"
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
	run_xapi_mcp
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
  *.op.read.XXXXXX) exec "$REAL_MKTEMP" "$@" ;;
  *) exit 1 ;;
esac
'
	export OP_READ_TOKEN='fresh-token'
	export DOTFILES_HERMES_REFRESH_SERVICE_ACCOUNT=1
	run_xapi_mcp
	status=$status
	output=$output
	[ "$status" -ne 0 ]
	! grep -q '^xurl ' "$COMMAND_LOG"
	[ "$(cat "$HOME/.hermes/.op.env")" = 'OP_SERVICE_ACCOUNT_TOKEN=old-token' ]
	[ "$(service_account_cache_mode)" = 600 ]
}

@test "fails preflight before native xurl when op is unavailable" {
	run_xapi_mcp op

	[ "$status" -ne 0 ]
	[[ "$output" == *"1Password CLI (op) is required"* ]]
	[ ! -s "$COMMAND_LOG" ]
}

@test "fails preflight before native xurl when jq is unavailable" {
	run_xapi_mcp jq

	[ "$status" -ne 0 ]
	[[ "$output" == *"jq is required"* ]]
	[ ! -s "$COMMAND_LOG" ]
}

@test "fails preflight before native xurl when yq is unavailable" {
	run_xapi_mcp yq

	[ "$status" -ne 0 ]
	[[ "$output" == *"yq is required"* ]]
	[ ! -s "$COMMAND_LOG" ]
}
