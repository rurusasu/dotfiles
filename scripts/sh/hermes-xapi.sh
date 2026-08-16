#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd -P)"

. "$SCRIPT_DIR/install-common.sh"
. "$SCRIPT_DIR/hermes-agent.sh"

compose_file="${HERMES_COMPOSE_FILE:-$REPO_ROOT/docker/hermes-agent/compose.yml}"
command_name="${1:-}"

dotfiles_hermes_sync_xapi_token_to_1password() {
  local data_dir cache_path item_file account vault item op_command

  data_dir="$(dotfiles_hermes_data_dir)"
  cache_path="$data_dir/.xurl/auth.yml"
  [[ -f $cache_path && ! -L $cache_path ]] ||
    dotfiles_die "xurl OAuth cache is missing: $cache_path"
  [[ $(stat -c '%a' "$cache_path" 2>/dev/null || stat -f '%Lp' "$cache_path") == 600 ]] ||
    dotfiles_die "xurl OAuth cache must have mode 0600."
  dotfiles_have python3 || dotfiles_die "python3 is required to sync the xurl refresh token."

  op_command="$(dotfiles_hermes_op_command)" ||
    dotfiles_die "1Password CLI (op) is required to sync the xurl refresh token."
  account="$(dotfiles_hermes_xapi_secret_account)"
  vault="$(dotfiles_hermes_xapi_secret_vault)"
  item="$(dotfiles_hermes_xapi_secret_item)"
  item_file="$(mktemp "$data_dir/.xapi-item.XXXXXX")" ||
    dotfiles_die "Could not create a temporary 1Password item file."
  chmod 600 "$item_file"
  trap 'rm -f -- "$item_file"' RETURN

  "$op_command" signin --account "$account" >/dev/null || true
  "$op_command" item get "$item" --account "$account" --vault "$vault" --format json >"$item_file"
  python3 - "$item_file" "$cache_path" <<'PY' | "$op_command" item edit "$item" --account "$account" --vault "$vault" >/dev/null
import json
import re
import sys

item_path, cache_path = sys.argv[1:]
item = json.load(open(item_path, encoding="utf-8"))
cache = open(cache_path, encoding="utf-8").read()
match = re.search(r"(?m)^\s+refresh_token:\s*(?:\"([^\"]+)\"|'([^']+)'|([^\s#]+))\s*$", cache)
if match is None:
    raise SystemExit("xurl refresh token is missing")
refresh_token = next(value for value in match.groups() if value is not None)
fields = [
    field for field in item.get("fields", [])
    if field.get("label") == "X_API_REFRESH_TOKEN"
    and (field.get("section") or {}).get("label") == "Refresh Token"
]
if len(fields) != 1:
    raise SystemExit("Refresh Token/X_API_REFRESH_TOKEN field is missing or duplicated")
fields[0]["value"] = refresh_token
sys.stdout.write(json.dumps(item, separators=(",", ":")))
PY
}

case "$command_name" in
auth)
  dotfiles_hermes_prepare_runtime_home
  dotfiles_hermes_with_xapi_credentials \
    docker compose -f "$compose_file" run --rm --no-deps --entrypoint /bin/sh xapi-mcp \
    -lc 'CLIENT_ID="$X_API_CLIENT_ID" CLIENT_SECRET="$X_API_CLIENT_SECRET" node_modules/.bin/xurl auth oauth2 --headless'
  ;;
sync-token)
  dotfiles_hermes_prepare_runtime_home
  dotfiles_hermes_sync_xapi_token_to_1password
  ;;
restart)
  dotfiles_hermes_prepare_runtime_home
  dotfiles_hermes_with_xapi_credentials_and_cache \
    docker compose -f "$compose_file" up -d --force-recreate xapi-mcp
  ;;
up)
  dotfiles_hermes_prepare_runtime_home
  dotfiles_hermes_with_xapi_credentials_and_cache \
    docker compose -f "$compose_file" up -d --force-recreate
  ;;
*)
  printf 'Usage: %s {auth|sync-token|restart|up}\n' "$0" >&2
  exit 64
  ;;
esac
