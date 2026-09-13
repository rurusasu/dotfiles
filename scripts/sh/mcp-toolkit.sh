#!/usr/bin/env bash

set -euo pipefail

profile_id="dotfiles"
profile_ref="${MCP_TOOLKIT_PROFILE_REF:-ghcr.io/rurusasu/dotfiles/mcp-profile:latest}"
secret_account="${MCP_TOOLKIT_OP_ACCOUNT:-my.1password.com}"
secret_timeout_seconds="${MCP_TOOLKIT_OP_TIMEOUT_SECONDS:-15}"

secret_specs=(
  "exa.api_key|op://openclaw/ExaUsedOpenclawPAT/credential"
  "firecrawl.api_key|op://openclaw/FirecrawlUsedOpenclawPAT/credential"
  "github.personal_access_token|op://openclaw/GitHubUsedOpenClawPAT/credential"
  "tavily.api_token|op://openclaw/TavilyUsedOpenclawPAT/credential"
)

toolkit_clients=(
  "codex"
  "cursor"
  "gemini"
  "vscode"
  "zed"
)

catalog_refs=(
  "catalog://mcp/docker-mcp-catalog/context7"
  "catalog://mcp/docker-mcp-catalog/deepwiki"
  "catalog://mcp/docker-mcp-catalog/exa"
  "catalog://mcp/docker-mcp-catalog/firecrawl"
  "catalog://mcp/docker-mcp-catalog/github-official"
  "catalog://mcp/docker-mcp-catalog/obsidian"
  "catalog://mcp/docker-mcp-catalog/playwright"
  "catalog://mcp/docker-mcp-catalog/tavily"
)

stale_servers=(
  "github"
  "linear"
  "sentry"
  "cloud-run"
  "superlocalmemory"
  "qmd"
  "hindsight"
)

require_docker_mcp() {
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

connect_clients() {
  local client
  for client in "${toolkit_clients[@]}"; do
    printf '%s\n' "[mcp-toolkit] connecting $client to profile $profile_id"
    docker mcp client connect --global --profile "$profile_id" --quiet "$client"
  done
}

ensure_profile() {
  if docker mcp profile show "$profile_id" >/dev/null 2>&1; then
    return
  fi

  printf '%s\n' "[mcp-toolkit] creating profile $profile_id"
  docker mcp profile create --id "$profile_id" --name "$profile_id"
}

sync_profile() {
  ensure_profile

  local server_args=(mcp profile server add "$profile_id")
  local ref
  for ref in "${catalog_refs[@]}"; do
    server_args+=(--server "$ref")
  done
  printf '%s\n' "[mcp-toolkit] converging catalog servers"
  docker "${server_args[@]}"

  local stale
  for stale in "${stale_servers[@]}"; do
    docker mcp profile server remove "$profile_id" --name "$stale" >/dev/null 2>&1 || true
  done

  printf '%s\n' "[mcp-toolkit] profile $profile_id"
  docker mcp profile show "$profile_id"
}

push_profile() {
  sync_profile
  printf '%s\n' "[mcp-toolkit] pushing $profile_id to $profile_ref"
  docker mcp profile push "$profile_id" "$profile_ref"
}

pull_profile() {
  printf '%s\n' "[mcp-toolkit] pulling profile from $profile_ref"
  docker mcp profile pull "$profile_ref"
  printf '%s\n' "[mcp-toolkit] profile $profile_id"
  docker mcp profile show "$profile_id"
}

show_status() {
  docker mcp profile show "$profile_id"
}

main() {
  local action="${1:-sync}"
  require_docker_mcp

  case "$action" in
  sync)
    sync_profile
    ;;
  push)
    push_profile
    ;;
  pull)
    pull_profile
    ;;
  secrets)
    sync_secrets
    ;;
  clients)
    connect_clients
    ;;
  status)
    show_status
    ;;
  *)
    printf 'Usage: %s {sync|push|pull|secrets|clients|status}\n' "$(basename "$0")" >&2
    exit 64
    ;;
  esac
}

main "$@"
