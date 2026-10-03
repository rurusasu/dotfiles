#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd -P)"

. "$SCRIPT_DIR/install-common.sh"

hindsight_env_value() {
  local compose_file="$1" key="$2" env_file line value found=0
  if [[ -n ${HINDSIGHT_ENV_FILE:-} ]]; then
    env_file="$HINDSIGHT_ENV_FILE"
  else
    env_file="$(dirname "$compose_file")/hindsight.env"
    [[ -f $env_file ]] || env_file="$REPO_ROOT/docker/hindsight/hindsight.env"
  fi
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

hindsight_stop_after_startup_failure() {
  local startup_status="$?"
  trap - EXIT
  if ((startup_status != 0)); then
    if ! docker compose -f "$compose_file" stop hindsight >/dev/null 2>&1; then
      printf 'Unable to stop the failed Hindsight service.\n' >&2
    fi
  fi
  exit "$startup_status"
}

hindsight_prepare() {
  local compose_file="$1" data_dir llm_model embedding_model ollama_command
  ollama_command="${DOTFILES_HINDSIGHT_OLLAMA_EXECUTABLE:-ollama}"
  for command in docker "$ollama_command" curl jq; do
    dotfiles_have "$command" || dotfiles_die "$command is required for Hindsight."
  done

  llm_model="$(hindsight_env_value "$compose_file" HINDSIGHT_OLLAMA_LLM_MODEL)"
  embedding_model="$(hindsight_env_value "$compose_file" HINDSIGHT_OLLAMA_EMBEDDING_MODEL)"
  data_dir="${HINDSIGHT_DATA_DIR:-$HOME/.local/share/hindsight}"
  "$ollama_command" pull "$llm_model"
  "$ollama_command" pull "$embedding_model"

  mkdir -p "$data_dir/pg0" "$data_dir/cache"
  docker compose -f "$compose_file" config --quiet
  hindsight_pull_image "$compose_file"
}

hindsight_pull_image() {
  local compose_file="$1" image
  if docker compose -f "$compose_file" pull hindsight; then
    return 0
  fi

  image="$(docker compose -f "$compose_file" config --images | sed -n '1p')"
  if [[ -n $image ]] && docker image inspect "$image" >/dev/null 2>&1; then
    printf 'Image pull failed; continuing with the cached Hindsight image.\n' >&2
    return 0
  fi

  dotfiles_die "Could not pull the Hindsight image and no cached image is available."
}

hindsight_up() {
  local compose_file="$1" startup_status
  hindsight_prepare "$compose_file"

  set +e
  (
    trap hindsight_stop_after_startup_failure EXIT
    set -e
    docker compose -f "$compose_file" up -d --force-recreate --remove-orphans hindsight
    hindsight_wait_for_api
  )
  startup_status=$?
  set -e
  return "$startup_status"
}

hindsight_verify() {
  local compose_file="$1"
  docker compose -f "$compose_file" config --quiet
  hindsight_wait_for_api
  printf 'Hindsight is healthy and database-connected.\n'
}

main() {
  local action="${1:-}" compose_file="${2:-$REPO_ROOT/docker/local-ai-services/compose.yml}"
  case "$action" in
  up) hindsight_up "$compose_file" ;;
  verify) hindsight_verify "$compose_file" ;;
  *) dotfiles_die "Usage: $0 {up|verify} [compose-file]" ;;
  esac
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
