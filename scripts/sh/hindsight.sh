#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd -P)"

. "$SCRIPT_DIR/install-common.sh"

hindsight_env_value() {
  local compose_file="$1" key="$2" env_file line value found=0
  env_file="$(dirname "$compose_file")/hindsight.env"
  [[ -f $env_file && ! -L $env_file ]] || dotfiles_die "Hindsight environment file is unavailable: $env_file"

  while IFS= read -r line || [[ -n $line ]]; do
    [[ $line == "$key="* ]] || continue
    value="${line#"$key="}"
    ((found += 1))
  done <"$env_file"
  ((found == 1)) || dotfiles_die "Hindsight environment value $key must occur exactly once."
  printf '%s\n' "$value"
}

hindsight_wait_for_api() {
  local attempts="${HINDSIGHT_API_READY_ATTEMPTS:-150}"
  local delay="${HINDSIGHT_API_READY_DELAY_SECONDS:-2}"
  local port="${HINDSIGHT_API_PORT:-8888}"
  local attempt health

  for ((attempt = 1; attempt <= attempts; attempt++)); do
    health="$(curl --fail --silent --show-error --max-time 2 "http://127.0.0.1:${port}/health" 2>/dev/null || true)"
    if [[ -n $health ]] && printf '%s\n' "$health" | jq -e \
      '.status == "healthy" and .database == "connected"' >/dev/null; then
      return 0
    fi
    ((attempt == attempts)) || sleep "$delay"
  done
  dotfiles_die "Hindsight API did not become ready after $attempts attempts."
}

hindsight_prepare() {
  local compose_file="$1" data_dir llm_model embedding_model
  for command in docker ollama curl jq; do
    dotfiles_have "$command" || dotfiles_die "$command is required for Hindsight."
  done

  llm_model="$(hindsight_env_value "$compose_file" HINDSIGHT_API_LLM_MODEL)"
  embedding_model="$(hindsight_env_value "$compose_file" HINDSIGHT_API_EMBEDDINGS_OPENAI_MODEL)"
  ollama pull "$llm_model"
  ollama pull "$embedding_model"

  data_dir="${HINDSIGHT_DATA_DIR:-$HOME/.local/share/hindsight}"
  mkdir -p "$data_dir/pg0" "$data_dir/cache"
  docker compose -f "$compose_file" config --quiet
}

hindsight_up() {
  local compose_file="$1"
  hindsight_prepare "$compose_file"
  docker compose -f "$compose_file" up -d hindsight
  hindsight_wait_for_api
}

hindsight_verify() {
  local compose_file="$1"
  docker compose -f "$compose_file" config --quiet
  hindsight_wait_for_api
  printf 'Hindsight is healthy and database-connected.\n'
}

main() {
  local action="${1:-}" compose_file="${2:-$REPO_ROOT/docker/hindsight/compose.yml}"
  case "$action" in
  up) hindsight_up "$compose_file" ;;
  verify) hindsight_verify "$compose_file" ;;
  *) dotfiles_die "Usage: $0 {up|verify} [compose-file]" ;;
  esac
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
