#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd -P)"

. "$SCRIPT_DIR/install-common.sh"
. "$SCRIPT_DIR/hermes-agent.sh"

compose_file="${HERMES_COMPOSE_FILE:-$REPO_ROOT/docker/hermes-agent/compose.yml}"
command_name="${1:-}"

case "$command_name" in
auth)
  dotfiles_hermes_prepare_runtime_home
  dotfiles_hermes_with_xapi_credentials \
    docker compose -f "$compose_file" run --rm --no-deps --entrypoint /bin/sh xapi-mcp \
    -lc 'CLIENT_ID="$X_API_CLIENT_ID" CLIENT_SECRET="$X_API_CLIENT_SECRET" node_modules/.bin/xurl auth oauth2 --headless'
  ;;
restart)
  dotfiles_hermes_prepare_runtime_home
  dotfiles_hermes_with_xapi_credentials \
    docker compose -f "$compose_file" up -d --force-recreate xapi-mcp
  ;;
up)
  dotfiles_hermes_prepare_runtime_home
  dotfiles_hermes_with_xapi_credentials \
    docker compose -f "$compose_file" up -d --force-recreate
  ;;
*)
  printf 'Usage: %s {auth|restart|up}\n' "$0" >&2
  exit 64
  ;;
esac
