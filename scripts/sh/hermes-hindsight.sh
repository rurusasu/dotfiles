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

dotfiles_hermes_hindsight_ollama_command() {
  local configured="${DOTFILES_HERMES_OLLAMA_EXECUTABLE:-}"

  if [[ -n $configured ]]; then
    if [[ $configured != /* || ! -x $configured ]]; then
      printf 'DOTFILES_HERMES_OLLAMA_EXECUTABLE must be an absolute executable path.\n' >&2
      return 1
    fi
    printf '%s\n' "$configured"
    return 0
  fi

  dotfiles_have ollama || {
    printf 'ollama is required for Hermes Hindsight.\n' >&2
    return 1
  }
  printf 'ollama\n'
}

dotfiles_hermes_hindsight_curl_command() {
  local configured="${DOTFILES_HERMES_CURL_EXECUTABLE:-}"

  if [[ -n $configured ]]; then
    if [[ $configured != /* || ! -x $configured ]]; then
      printf 'DOTFILES_HERMES_CURL_EXECUTABLE must be an absolute executable path.\n' >&2
      return 1
    fi
    printf '%s\n' "$configured"
    return 0
  fi

  dotfiles_have curl || {
    printf 'curl is required for Hermes Hindsight.\n' >&2
    return 1
  }
  printf 'curl\n'
}

dotfiles_hermes_hindsight_ollama_url() {
  local url="${HINDSIGHT_OLLAMA_URL:-http://127.0.0.1:11434}"

  if [[ ! $url =~ ^http://[A-Za-z0-9.-]+:[1-9][0-9]*$ ]]; then
    printf 'HINDSIGHT_OLLAMA_URL must be an HTTP host and port.\n' >&2
    return 1
  fi
  printf '%s\n' "$url"
}

dotfiles_hermes_hindsight_configure_ollama_url() {
  local docker_runner="$1" gateway

  if [[ -n ${HINDSIGHT_OLLAMA_URL:-} ]]; then
    dotfiles_hermes_hindsight_ollama_url >/dev/null
    return
  fi
  if [[ $(uname -s) != Linux ]]; then
    export HINDSIGHT_OLLAMA_URL=http://127.0.0.1:11434
    return
  fi

  gateway="$("$docker_runner" network inspect bridge --format '{{(index .IPAM.Config 0).Gateway}}')" || {
    printf 'Unable to resolve the Docker bridge gateway for Ollama.\n' >&2
    return 1
  }
  if [[ ! $gateway =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    printf 'Docker bridge returned an invalid Ollama gateway: %s\n' "$gateway" >&2
    return 1
  fi
  export HINDSIGHT_OLLAMA_URL="http://${gateway}:11434"
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
  local attempts delay_seconds timeout_seconds attempt curl_command ollama_url

  attempts="$(dotfiles_hermes_hindsight_positive_integer "${HINDSIGHT_OLLAMA_READY_ATTEMPTS:-30}" 30)"
  delay_seconds="$(dotfiles_hermes_hindsight_nonnegative_integer "${HINDSIGHT_OLLAMA_READY_DELAY_SECONDS:-2}" 2)"
  timeout_seconds="$(dotfiles_hermes_hindsight_positive_integer "${HINDSIGHT_OLLAMA_PROBE_TIMEOUT_SECONDS:-2}" 2)"
  curl_command="$(dotfiles_hermes_hindsight_curl_command)" || return 1
  ollama_url="$(dotfiles_hermes_hindsight_ollama_url)" || return 1

  for ((attempt = 1; attempt <= attempts; attempt++)); do
    if "$curl_command" --fail --silent --show-error --max-time "$timeout_seconds" \
      "$ollama_url/api/version" >/dev/null 2>&1; then
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
  local model="$1" timeout_seconds="$2" tags curl_command ollama_url

  curl_command="$(dotfiles_hermes_hindsight_curl_command)" || return 1
  ollama_url="$(dotfiles_hermes_hindsight_ollama_url)" || return 1
  tags="$("$curl_command" --fail --silent --show-error --max-time "$timeout_seconds" \
    "$ollama_url/api/tags")" || return 1
  printf '%s\n' "$tags" | jq -e --arg model "$model" \
    '.models | any(.name == $model)' >/dev/null
}

dotfiles_hermes_hindsight_prepare_host() {
  local compose_file="$1" llm_model embedding_model timeout_seconds pull_timeout_seconds
  local timeout_command data_dir ollama_command ollama_url ollama_host

  ollama_command="$(dotfiles_hermes_hindsight_ollama_command)" || return 1
  dotfiles_hermes_hindsight_curl_command >/dev/null || return 1
  dotfiles_have jq || {
    printf 'jq is required for Hermes Hindsight.\n' >&2
    return 1
  }
  timeout_command="$(dotfiles_hermes_hindsight_gnu_timeout)" || return 1
  dotfiles_hermes_hindsight_wait_for_ollama || return $?
  ollama_url="$(dotfiles_hermes_hindsight_ollama_url)" || return 1
  ollama_host="${ollama_url#http://}"
  llm_model="$(dotfiles_hermes_hindsight_env_value "$compose_file" HINDSIGHT_API_LLM_MODEL)" || return 1
  embedding_model="$(dotfiles_hermes_hindsight_env_value "$compose_file" HINDSIGHT_API_EMBEDDINGS_OPENAI_MODEL)" || return 1
  timeout_seconds="$(dotfiles_hermes_hindsight_positive_integer "${HINDSIGHT_OLLAMA_PROBE_TIMEOUT_SECONDS:-2}" 2)"
  pull_timeout_seconds="$(dotfiles_hermes_hindsight_positive_integer "${HINDSIGHT_OLLAMA_PULL_TIMEOUT_SECONDS:-3600}" 3600)"

  OLLAMA_HOST="$ollama_host" "$timeout_command" --foreground --kill-after=30 "$pull_timeout_seconds" \
    "$ollama_command" pull "$llm_model" || return $?
  OLLAMA_HOST="$ollama_host" "$timeout_command" --foreground --kill-after=30 "$pull_timeout_seconds" \
    "$ollama_command" pull "$embedding_model" || return $?
  dotfiles_hermes_hindsight_verify_model "$llm_model" "$timeout_seconds" || return 1
  dotfiles_hermes_hindsight_verify_model "$embedding_model" "$timeout_seconds" || return 1

  data_dir="$(dotfiles_hermes_data_dir)"
  mkdir -p "$data_dir/hindsight/pg0" "$data_dir/hindsight/cache"
}

dotfiles_hermes_hindsight_wait_for_api() {
  local attempts delay_seconds timeout_seconds port attempt health curl_command

  attempts="$(dotfiles_hermes_hindsight_positive_integer "${HINDSIGHT_API_READY_ATTEMPTS:-150}" 150)"
  delay_seconds="$(dotfiles_hermes_hindsight_nonnegative_integer "${HINDSIGHT_API_READY_DELAY_SECONDS:-2}" 2)"
  timeout_seconds="$(dotfiles_hermes_hindsight_positive_integer "${HINDSIGHT_API_PROBE_TIMEOUT_SECONDS:-2}" 2)"
  port="${HINDSIGHT_API_PORT:-8888}"
  curl_command="$(dotfiles_hermes_hindsight_curl_command)" || return 1

  for ((attempt = 1; attempt <= attempts; attempt++)); do
    health="$("$curl_command" --fail --silent --show-error --max-time "$timeout_seconds" \
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
