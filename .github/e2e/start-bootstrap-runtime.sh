#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
COMPOSE_FILE="$REPO_ROOT/docker/hermes-service/compose.yml"

[[ -f $COMPOSE_FILE ]] || {
	printf 'acceptance Compose file is missing: %s\n' "$COMPOSE_FILE" >&2
	exit 1
}

# The acceptance Compose file intentionally uses the production external
# network contract. Create that network in the isolated runner/VM before
# starting every service so --runtime verifies a real, complete stack.
if ! docker network inspect local-ai-services >/dev/null 2>&1; then
	docker network create local-ai-services >/dev/null
fi

docker compose -f "$COMPOSE_FILE" up --detach --wait
