#!/usr/bin/env bash

dotfiles_hermes_hindsight_env_file() {
  local compose_file="$1"

  printf '%s/hindsight.env\n' "$(dirname "$compose_file")"
}

dotfiles_hermes_hindsight_env_value() {
  local compose_file="$1" key="$2" env_file line value found=0

  [[ $key =~ ^[A-Z][A-Z0-9_]*$ ]] || return 1
  env_file="$(dotfiles_hermes_hindsight_env_file "$compose_file")" || return 1
  [[ -f $env_file && ! -L $env_file ]] || {
    printf 'Hindsight environment file is unavailable: %s\n' "$env_file" >&2
    return 1
  }

  while IFS= read -r line || [[ -n $line ]]; do
    [[ $line == "$key="* ]] || continue
    value="${line#"$key="}"
    [[ -n $value && $value != *$'\r'* && $value != *$'\n'* ]] || {
      printf 'Hindsight environment value %s must be nonempty.\n' "$key" >&2
      return 1
    }
    ((found += 1))
    if ((found > 1)); then
      printf 'Hindsight environment value %s must not be duplicated.\n' "$key" >&2
      return 1
    fi
  done <"$env_file"

  ((found == 1)) || {
    printf 'Hindsight environment value %s is missing.\n' "$key" >&2
    return 1
  }
  printf '%s\n' "$value"
}

dotfiles_hermes_hindsight_positive_integer() {
  local value="$1" default_value="$2"

  [[ $value =~ ^[1-9][0-9]*$ ]] || value="$default_value"
  printf '%s\n' "$value"
}

dotfiles_hermes_hindsight_nonnegative_integer() {
  local value="$1" default_value="$2"

  [[ $value =~ ^[0-9]+$ ]] || value="$default_value"
  printf '%s\n' "$value"
}

dotfiles_hermes_hindsight_gnu_timeout() {
  local candidate version

  for candidate in timeout gtimeout; do
    dotfiles_have "$candidate" || continue
    version="$("$candidate" --version 2>/dev/null)" || continue
    if [[ $version == *"GNU coreutils"* ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  printf 'GNU timeout is required for Hermes Hindsight model pulls.\n' >&2
  return 1
}

dotfiles_hermes_hindsight_wait_for_ollama() {
  local attempts delay_seconds timeout_seconds attempt

  attempts="$(dotfiles_hermes_hindsight_positive_integer "${HINDSIGHT_OLLAMA_READY_ATTEMPTS:-30}" 30)"
  delay_seconds="$(dotfiles_hermes_hindsight_nonnegative_integer "${HINDSIGHT_OLLAMA_READY_DELAY_SECONDS:-2}" 2)"
  timeout_seconds="$(dotfiles_hermes_hindsight_positive_integer "${HINDSIGHT_OLLAMA_PROBE_TIMEOUT_SECONDS:-2}" 2)"

  for ((attempt = 1; attempt <= attempts; attempt++)); do
    if curl --fail --silent --show-error --max-time "$timeout_seconds" \
      http://127.0.0.1:11434/api/version >/dev/null 2>&1; then
      return 0
    fi
    if ((attempt < attempts)); then
      sleep "$delay_seconds"
    fi
  done

  printf 'Ollama API did not become ready after %s attempts.\n' "$attempts" >&2
  return 1
}

dotfiles_hermes_hindsight_verify_model() {
  local model="$1" timeout_seconds="$2" tags

  tags="$(curl --fail --silent --show-error --max-time "$timeout_seconds" \
    http://127.0.0.1:11434/api/tags)" || return 1
  printf '%s\n' "$tags" | jq -e --arg model "$model" \
    '.models | any(.name == $model)' >/dev/null
}

dotfiles_hermes_hindsight_prepare_host() {
  local compose_file="$1" llm_model embedding_model timeout_seconds pull_timeout_seconds
  local timeout_command data_dir

  dotfiles_have ollama || {
    printf 'ollama is required for Hermes Hindsight.\n' >&2
    return 1
  }
  dotfiles_have curl || {
    printf 'curl is required for Hermes Hindsight.\n' >&2
    return 1
  }
  dotfiles_have jq || {
    printf 'jq is required for Hermes Hindsight.\n' >&2
    return 1
  }
  timeout_command="$(dotfiles_hermes_hindsight_gnu_timeout)" || return 1
  dotfiles_hermes_hindsight_wait_for_ollama || return $?
  llm_model="$(dotfiles_hermes_hindsight_env_value "$compose_file" HINDSIGHT_API_LLM_MODEL)" || return 1
  embedding_model="$(dotfiles_hermes_hindsight_env_value "$compose_file" HINDSIGHT_API_EMBEDDINGS_OPENAI_MODEL)" || return 1
  timeout_seconds="$(dotfiles_hermes_hindsight_positive_integer "${HINDSIGHT_OLLAMA_PROBE_TIMEOUT_SECONDS:-2}" 2)"
  pull_timeout_seconds="$(dotfiles_hermes_hindsight_positive_integer "${HINDSIGHT_OLLAMA_PULL_TIMEOUT_SECONDS:-3600}" 3600)"

  "$timeout_command" --foreground --kill-after=30 "$pull_timeout_seconds" \
    ollama pull "$llm_model" || return $?
  "$timeout_command" --foreground --kill-after=30 "$pull_timeout_seconds" \
    ollama pull "$embedding_model" || return $?
  dotfiles_hermes_hindsight_verify_model "$llm_model" "$timeout_seconds" || return 1
  dotfiles_hermes_hindsight_verify_model "$embedding_model" "$timeout_seconds" || return 1

  data_dir="$(dotfiles_hermes_data_dir)"
  mkdir -p "$data_dir/hindsight/pg0" "$data_dir/hindsight/cache"
}

dotfiles_hermes_hindsight_wait_for_api() {
  local attempts delay_seconds timeout_seconds port attempt health

  attempts="$(dotfiles_hermes_hindsight_positive_integer "${HINDSIGHT_API_READY_ATTEMPTS:-150}" 150)"
  delay_seconds="$(dotfiles_hermes_hindsight_nonnegative_integer "${HINDSIGHT_API_READY_DELAY_SECONDS:-2}" 2)"
  timeout_seconds="$(dotfiles_hermes_hindsight_positive_integer "${HINDSIGHT_API_PROBE_TIMEOUT_SECONDS:-2}" 2)"
  port="${HINDSIGHT_API_PORT:-8888}"

  for ((attempt = 1; attempt <= attempts; attempt++)); do
    health="$(curl --fail --silent --show-error --max-time "$timeout_seconds" \
      "http://127.0.0.1:${port}/health")" || health=""
    if [[ -n $health ]] && printf '%s\n' "$health" |
      jq -e '.status == "healthy" and .database == "connected"' >/dev/null; then
      return 0
    fi
    if ((attempt < attempts)); then
      sleep "$delay_seconds"
    fi
  done

  printf 'Hindsight API did not become ready after %s attempts.\n' "$attempts" >&2
  return 1
}

dotfiles_hermes_hindsight_start() {
  local docker_runner="$1" compose_file="$2"

  "$docker_runner" compose -f "$compose_file" up -d hindsight || return $?
  dotfiles_hermes_hindsight_wait_for_api
}
