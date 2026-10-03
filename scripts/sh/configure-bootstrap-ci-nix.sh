#!/usr/bin/env bash
# Configure only disposable CI users; do not persist credentials in the image.
set -euo pipefail

if [[ $# -gt 1 || (${1:-} != "" && ${1:-} != --wsl) ]]; then
  echo "Usage: $0 [--wsl]" >&2
  exit 64
fi
: "${GITHUB_TOKEN:?GitHub token is required for CI Nix fetches}"
if [[ $GITHUB_TOKEN == *[[:space:]]* ]]; then
  echo "GitHub token must not contain whitespace." >&2
  exit 1
fi

# Git and Nix/libgit2 must trust the runner-owned checkout in this disposable
# root container, including tests that reset HOME. Do not trust other paths.
if [[ ${1:-} != --wsl ]]; then
  : "${GITHUB_WORKSPACE:?CI checkout path is required}"
  [[ $GITHUB_WORKSPACE == /* ]] || exit 64
  git config --system --replace-all safe.directory "$GITHUB_WORKSPACE"
fi

config_home="${XDG_CONFIG_HOME:-}"
if [[ -z $config_home ]]; then
  nix_home="$HOME"
  # Nix rejects the runner-owned HOME mount in root container jobs.
  if [[ ! -O $nix_home ]]; then
    nix_home=$(getent passwd "$(id -u)" | cut -d: -f6)
    [[ $nix_home == /* ]] || {
      echo "Cannot resolve the Nix user's home." >&2
      exit 1
    }
  fi
  config_home="$nix_home/.config"
fi
config_dir="$config_home/nix"
config_file="$config_dir/bootstrap-ci.conf"
umask 077
mkdir -p "$config_dir"
{
  printf 'access-tokens = github.com=%s\n' "$GITHUB_TOKEN"
  if [[ ${1:-} == --wsl ]]; then
    repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
    # Keep container-only store ownership and sandbox settings out of NixOS.
    grep -E '^(experimental-features|extra-substituters|extra-trusted-public-keys) = ' \
      "$repo_root/docker/bootstrap-ci-tools/nix.conf"
    printf 'max-jobs = 2\ncores = 1\n'
  fi
} >"$config_file"
chmod 600 "$config_file"

include="include $config_file"
touch "$config_dir/nix.conf"
if ! grep -Fxq "$include" "$config_dir/nix.conf"; then
  printf '\n%s\n' "$include" >>"$config_dir/nix.conf"
fi

# Validate without printing credentials to the log.
if ! nix config show access-tokens | grep -E '^[[:space:]]*github\.com[[:space:]]*=[[:space:]]*[^[:space:]]+' >/dev/null; then
  echo "Nix did not load the CI GitHub authentication configuration." >&2
  exit 1
fi
