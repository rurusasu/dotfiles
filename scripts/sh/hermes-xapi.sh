#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

. "$SCRIPT_DIR/install-common.sh"
. "$SCRIPT_DIR/hermes-xapi-common.sh"

command_name="${1:-}"

case "$command_name" in
auth)
  dotfiles_hermes_require_xapi_tools
  dotfiles_hermes_prepare_runtime_home
  dotfiles_hermes_with_xapi_credentials \
    xurl auth oauth2 --headless
  ;;
sync-token)
  dotfiles_hermes_require_xapi_tools
  dotfiles_hermes_prepare_runtime_home
  dotfiles_hermes_prepare_service_account_environment ||
    dotfiles_die "Hermes 1Password Service Account is unavailable."
  dotfiles_hermes_sync_xapi_refresh_token_to_onepassword
  ;;
mcp)
  dotfiles_hermes_require_xapi_tools
  dotfiles_hermes_prepare_runtime_home
  dotfiles_hermes_ensure_xapi_auth >&2
  dotfiles_hermes_with_xapi_credentials xurl mcp https://api.x.com/mcp
  ;;
*)
  printf 'Usage: %s {auth|sync-token|mcp}\n' "$0" >&2
  exit 64
  ;;
esac
