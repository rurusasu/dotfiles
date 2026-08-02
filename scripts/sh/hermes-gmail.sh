#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd -P)"

compose_file="${HERMES_COMPOSE_FILE:-$REPO_ROOT/docker/hermes-agent/compose.yml}"
data_dir="${HERMES_DATA_DIR:-${USERPROFILE:-$HOME}/.hermes}"
action="${1:-}"
profile="${2:-}"

die() {
  printf '%s\n' "$1" >&2
  exit "${2:-1}"
}

resolve_profile_home() {
  case "$profile" in
  default)
    host_profile_home="$data_dir"
    container_profile_home="/opt/data"
    ;;
  *)
    [[ $profile =~ ^[a-z0-9][a-z0-9_-]*$ ]] ||
      die "Invalid Hermes profile: $profile" 64
    host_profile_home="$data_dir/profiles/$profile"
    container_profile_home="/opt/data/profiles/$profile"
    ;;
  esac

  [[ -d $host_profile_home && ! -L $host_profile_home ]] ||
    die "Hermes profile is not installed: $profile" 66
  host_profile_home="$(cd -P -- "$host_profile_home" && pwd)"
}

validate_token_cache_parent() {
  local cache_parent
  local expected_parent

  mkdir -p -m 700 -- "$host_profile_home/mcp-tokens"
  cache_parent="$host_profile_home/mcp-tokens"
  [[ -d $cache_parent && ! -L $cache_parent ]] ||
    die "Gmail token cache parent is invalid for profile: $profile"

  cache_parent="$(cd -P -- "$cache_parent" && pwd)"
  expected_parent="$host_profile_home/mcp-tokens"
  [[ $cache_parent == "$expected_parent" && $cache_parent == "$host_profile_home"/* ]] ||
    die "Gmail token cache parent is invalid for profile: $profile"
  token_cache="$cache_parent/gmail.json"
}

token_cache_is_private() {
  local mode

  [[ -f $token_cache && ! -L $token_cache ]] || return 1
  if mode="$(stat -f '%Lp' "$token_cache" 2>/dev/null)"; then
    :
  else
    mode="$(stat -c '%a' "$token_cache" 2>/dev/null)" || return 1
  fi
  [[ $mode == 600 ]]
}

require_private_token_cache() {
  validate_token_cache_parent
  token_cache_is_private ||
    die "Gmail OAuth token cache is missing or not private for profile: $profile"
}

[[ -n $profile ]] || die "Usage: $0 {auth|test} profile-name" 64
resolve_profile_home

case "$action" in
auth)
  validate_token_cache_parent
  docker compose -f "$compose_file" run --rm --no-deps \
    -e "HERMES_HOME=$container_profile_home" \
    hermes hermes mcp login gmail
  require_private_token_cache
  ;;
test)
  require_private_token_cache
  docker compose -f "$compose_file" run --rm --no-deps -T \
    -e "HERMES_HOME=$container_profile_home" \
    hermes hermes mcp test gmail
  ;;
*)
  die "Usage: $0 {auth|test} profile-name" 64
  ;;
esac
