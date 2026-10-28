#!/usr/bin/env bash

set -euo pipefail

secret_account="${MCP_TOOLKIT_OP_ACCOUNT:-my.1password.com}"
secret_timeout_seconds="${MCP_TOOLKIT_OP_TIMEOUT_SECONDS:-15}"

secret_specs=(
  "exa.api_key|op://openclaw/ExaUsedOpenclawPAT/credential"
  "firecrawl.api_key|op://openclaw/FirecrawlUsedOpenclawPAT/credential"
  "github.personal_access_token|op://openclaw/GitHubUsedOpenClawPAT/credential"
  "tavily.api_token|op://openclaw/TavilyUsedOpenclawPAT/credential"
)

require_docker_mcp() {
  : "${DOCKER_CONFIG:?Docker MCP requires DOCKER_CONFIG}"
  command -v docker >/dev/null 2>&1 || {
    printf '%s\n' "[mcp-toolkit] docker is required" >&2
    exit 127
  }

  docker mcp --help >/dev/null 2>&1 || {
    printf '%s\n' "[mcp-toolkit] Docker MCP Toolkit CLI is required" >&2
    exit 127
  }
}

require_op() {
  if command -v op >/dev/null 2>&1; then
    op_command="$(command -v op)"
  elif command -v op.exe >/dev/null 2>&1; then
    op_command="$(command -v op.exe)"
  else
    printf '%s\n' "[mcp-toolkit] 1Password CLI (op) is required" >&2
    exit 127
  fi
}

read_onepassword_secret() {
  local ref="$1"
  local op_args=(read --no-newline --account "$secret_account" "$ref")

  if [[ $op_command == *op.exe ]]; then
    op_args=(--cache=false "${op_args[@]}")
  fi

  if command -v timeout >/dev/null 2>&1; then
    timeout --foreground "$secret_timeout_seconds" "$op_command" "${op_args[@]}"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$secret_timeout_seconds" "$op_command" "${op_args[@]}"
  else
    printf '%s\n' "[mcp-toolkit] timeout or gtimeout is required for 1Password reads" >&2
    return 127
  fi
}

sync_secrets() {
  require_op

  local spec key ref
  for spec in "${secret_specs[@]}"; do
    key="${spec%%|*}"
    ref="${spec#*|}"
    printf '%s\n' "[mcp-toolkit] injecting $key from 1Password"
    if ! read_onepassword_secret "$ref" | docker mcp secret set "$key" >/dev/null; then
      printf '%s\n' "[mcp-toolkit] failed to inject $key" >&2
      return 1
    fi
  done
}

main() {
  local action="${1:-status}"
  require_docker_mcp

  case "$action" in
  secrets)
    sync_secrets
    ;;
  status)
    docker mcp version
    ;;
  *)
    printf 'Usage: %s {secrets|status}\n' "$(basename "$0")" >&2
    exit 64
    ;;
  esac
}

main "$@"
