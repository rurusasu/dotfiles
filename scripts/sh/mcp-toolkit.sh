#!/usr/bin/env bash

set -euo pipefail

profile_id="dotfiles"
profile_ref="${MCP_TOOLKIT_PROFILE_REF:-ghcr.io/rurusasu/dotfiles/mcp-profile:latest}"

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
  status)
    show_status
    ;;
  *)
    printf 'Usage: %s {sync|push|pull|status}\n' "$(basename "$0")" >&2
    exit 64
    ;;
  esac
}

main "$@"
