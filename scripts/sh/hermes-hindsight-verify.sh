#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd -P)"

. "$SCRIPT_DIR/install-common.sh"
. "$SCRIPT_DIR/hermes-agent.sh"
. "$SCRIPT_DIR/hindsight.sh"

hermes_compose_file="${HERMES_COMPOSE_FILE:-$REPO_ROOT/docker/hermes-service/compose.yml}"
hindsight_compose_file="${HINDSIGHT_COMPOSE_FILE:-$REPO_ROOT/docker/local-ai-services/compose.yml}"
api_url="http://hindsight:8888"
ollama_url="http://host.docker.internal:11434"
state_file="/opt/data/hindsight/acceptance-state.json"
evidence_file="/opt/data/hindsight/acceptance.json"
profiles="default,rick,hoffman,risarisa,nancy,kuroda,shiraishi"

docker compose -f "$hermes_compose_file" config --quiet
hindsight_up "$hindsight_compose_file"

docker compose -f "$hermes_compose_file" exec -T hermes \
  hermes-hindsight-acceptance probe \
  --api-url "$api_url" \
  --ollama-url "$ollama_url" \
  --strict-probes 20 \
  --timeout 300 \
  --evidence "$evidence_file"

docker compose -f "$hermes_compose_file" exec -T hermes \
  hermes-hindsight-acceptance seed \
  --api-url "$api_url" \
  --profiles "$profiles" \
  --timeout 300 \
  --state "$state_file"

docker compose -f "$hindsight_compose_file" restart hindsight
hindsight_wait_for_api

docker compose -f "$hermes_compose_file" exec -T hermes \
  hermes-hindsight-acceptance verify \
  --api-url "$api_url" \
  --timeout 300 \
  --state "$state_file" \
  --evidence "$evidence_file"

restore_hindsight_on_exit() {
  local original_status=$?
  if [[ $hindsight_stopped == true ]]; then
    if docker compose -f "$hindsight_compose_file" start hindsight; then
      if ! hindsight_wait_for_api; then
        printf 'Warning: Hindsight restart did not become healthy during failure recovery.\n' >&2
      fi
    else
      printf 'Warning: Hindsight restart failed during failure recovery.\n' >&2
    fi
  fi
  return "$original_status"
}

hindsight_stopped=false
trap restore_hindsight_on_exit EXIT
docker compose -f "$hindsight_compose_file" stop hindsight
hindsight_stopped=true

docker compose -f "$hermes_compose_file" exec -T hermes \
  hermes-hindsight-acceptance degraded \
  --api-url "$api_url" \
  --timeout 5 \
  --state "$state_file" \
  --evidence "$evidence_file"

alive_response="$(
  docker compose -f "$hermes_compose_file" exec -T hermes \
    hermes chat --quiet -q "Reply with exactly HERMES_ALIVE and nothing else."
)"
final_response="$(printf '%s\n' "$alive_response" | awk 'NF { line = $0 } END { print line }')"
if [[ $final_response != HERMES_ALIVE ]]; then
  printf 'Hermes degraded one-shot must end with exact HERMES_ALIVE; got: %s\n' \
    "$final_response" >&2
  exit 1
fi

curl --fail --silent --show-error --max-time 5 \
  "http://127.0.0.1:${HERMES_API_PORT:-8642}/health" >/dev/null

docker compose -f "$hindsight_compose_file" start hindsight
hindsight_wait_for_api
hindsight_stopped=false

docker compose -f "$hermes_compose_file" exec -T hermes \
  hermes-hindsight-acceptance recovery \
  --api-url "$api_url" \
  --timeout 300 \
  --state "$state_file" \
  --evidence "$evidence_file"

docker compose -f "$hermes_compose_file" exec -T hermes \
  hermes-hindsight-acceptance cleanup \
  --api-url "$api_url" \
  --state "$state_file" \
  --evidence "$evidence_file"
trap - EXIT
