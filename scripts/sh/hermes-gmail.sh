#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
data_dir="${HERMES_DATA_DIR:-${USERPROFILE:-$HOME}/.hermes}"
action="${1:-}"
gmail_mcp_package="@artymclabin/gmail-mcp@1.2.3"

die() {
  printf '%s\n' "$1" >&2
  exit "${2:-1}"
}

file_mode() {
  stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null
}

resolve_shared_credentials() {
  [[ -d $data_dir && ! -L $data_dir ]] ||
    die "Hermes data directory is not installed" 66
  data_dir="$(cd -P -- "$data_dir" && pwd)"
  credentials_dir="$data_dir/google-gmail-mcp"
  oauth_file="$credentials_dir/gcp-oauth.keys.json"
  credentials_file="$credentials_dir/credentials.json"

  [[ -d $credentials_dir && ! -L $credentials_dir ]] ||
    die "Shared Gmail credential directory is missing or invalid"
  credentials_dir="$(cd -P -- "$credentials_dir" && pwd)"
  [[ $credentials_dir == "$data_dir/google-gmail-mcp" ]] ||
    die "Shared Gmail credential directory is missing or invalid"
  [[ -f $oauth_file && ! -L $oauth_file && $(file_mode "$oauth_file") == 600 ]] ||
    die "Shared Gmail OAuth client is missing or not private"
}

require_private_credentials() {
  resolve_shared_credentials
  [[ -f $credentials_file && ! -L $credentials_file && $(file_mode "$credentials_file") == 600 ]] ||
    die "Shared Gmail OAuth credentials are missing or not private"
}

case "$action" in
auth)
  resolve_shared_credentials
  GMAIL_OAUTH_PATH="$oauth_file" \
    GMAIL_CREDENTIALS_PATH="$credentials_file" \
    npx --yes "$gmail_mcp_package" auth \
    --scopes=gmail.readonly,gmail.compose
  chmod 600 "$credentials_file"
  require_private_credentials
  ;;
*)
  die "Usage: $0 auth" 64
  ;;
esac
