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

hindsight_migrate_legacy_data() {
  local data_dir="$1"
  local legacy_dir="${HERMES_DATA_DIR:-$HOME/.hermes}/hindsight"
  local existing staging component source marker legacy_container=0 legacy_has_memory=0

  [[ $legacy_dir != "$data_dir" && -e $legacy_dir ]] || return 0
  [[ -d $legacy_dir && ! -L $legacy_dir ]] ||
    dotfiles_die "Legacy Hindsight data path is not a regular directory: $legacy_dir"
  [[ ! -L $data_dir ]] || dotfiles_die "Hindsight data path must not be a symlink: $data_dir"

  for component in pg0 cache; do
    source="$legacy_dir/$component"
    [[ ! -e $source || (-d $source && ! -L $source) ]] ||
      dotfiles_die "Legacy Hindsight component is not a regular directory: $source"
    if [[ -d $source ]] && [[ -n $(find "$source" -mindepth 1 -print -quit) ]]; then
      legacy_has_memory=1
    fi
  done
  ((legacy_has_memory == 1)) || return 0

  marker="$data_dir/.legacy-migration-source"
  if [[ -f $marker && ! -L $marker && $(<"$marker") == "$legacy_dir" ]]; then
    return 0
  fi

  if [[ -d $data_dir ]]; then
    existing="$(find "$data_dir" -mindepth 1 \
      ! -path "$data_dir/pg0" ! -path "$data_dir/cache" -print -quit)"
    [[ -z $existing ]] ||
      dotfiles_die "Legacy and independent Hindsight data directories both contain data; migrate them manually: $legacy_dir -> $data_dir"
  elif [[ -e $data_dir ]]; then
    dotfiles_die "Hindsight data path is not a directory: $data_dir"
  fi

  if docker container inspect hindsight >/dev/null 2>&1; then
    docker stop hindsight >/dev/null
    legacy_container=1
  fi

  mkdir -p "$(dirname "$data_dir")"
  staging="${data_dir}.migrate.$$"
  [[ ! -e $staging ]] || dotfiles_die "Hindsight migration staging path already exists: $staging"
  mkdir "$staging"
  for component in pg0 cache; do
    source="$legacy_dir/$component"
    if [[ -d $source ]]; then
      cp -a "$source" "$staging/$component" ||
        dotfiles_die "Unable to copy legacy Hindsight data; the original remains at $legacy_dir"
    else
      mkdir "$staging/$component"
    fi
  done
  printf '%s\n' "$legacy_dir" >"$staging/.legacy-migration-source"
  chmod 600 "$staging/.legacy-migration-source"

  if [[ -d $data_dir ]]; then
    [[ ! -d $data_dir/pg0 ]] || rmdir "$data_dir/pg0"
    [[ ! -d $data_dir/cache ]] || rmdir "$data_dir/cache"
    rmdir "$data_dir"
  fi
  mv "$staging" "$data_dir"

  if ((legacy_container == 1)); then
    docker rm hindsight >/dev/null
  fi
  printf 'Migrated legacy Hindsight data to %s; the source was preserved at %s.\n' "$data_dir" "$legacy_dir"
}

hindsight_prepare() {
  local compose_file="$1" data_dir llm_model embedding_model
  for command in docker ollama curl jq; do
    dotfiles_have "$command" || dotfiles_die "$command is required for Hindsight."
  done

  llm_model="$(hindsight_env_value "$compose_file" HINDSIGHT_API_LLM_MODEL)"
  embedding_model="$(hindsight_env_value "$compose_file" HINDSIGHT_API_EMBEDDINGS_OPENAI_MODEL)"
  data_dir="${HINDSIGHT_DATA_DIR:-$HOME/.local/share/hindsight}"
  hindsight_migrate_legacy_data "$data_dir"
  ollama pull "$llm_model"
  ollama pull "$embedding_model"

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
