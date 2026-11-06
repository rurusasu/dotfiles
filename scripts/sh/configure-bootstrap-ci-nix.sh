#!/usr/bin/env bash
# Configure only disposable CI users; keep credentials in their private config.
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

# The native runner and explicit root activation each trust this checkout only
# in their own user configuration; no system-wide Git configuration is changed.
if [[ ${1:-} != --wsl ]]; then
  : "${GITHUB_WORKSPACE:?CI checkout path is required}"
  [[ $GITHUB_WORKSPACE == /* ]] || exit 64
  git config --global --replace-all safe.directory "$GITHUB_WORKSPACE"
fi

config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
config_dir="$config_home/nix"
config_file="$config_dir/bootstrap-ci.conf"
umask 077
mkdir -p "$config_dir"
{
  printf 'access-tokens = github.com=%s\n' "$GITHUB_TOKEN"
  repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
  # Share caches and transport limits across every CI platform. Replacing the
  # base substituter also preserves the official-cache priority after NixOS or
  # nix-darwin activation installs the host's normal configuration.
  cat "$repo_root/.github/nix.conf"
  if [[ -n ${DOTFILES_CI_BINARY_CACHE:-} ]]; then
    # This local cache is restored within GitHub's branch-scoped CI cache.
    [[ $DOTFILES_CI_BINARY_CACHE == /* && $DOTFILES_CI_BINARY_CACHE != *[[:space:]?]* ]] || exit 64
    # Own the directory before the root daemon opens this file substituter.
    mkdir -p "$DOTFILES_CI_BINARY_CACHE"
    printf 'extra-substituters = file://%s?trusted=true\n' "$DOTFILES_CI_BINARY_CACHE"
  fi
  if [[ ${1:-} == --wsl ]]; then
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
if ! nix config show substituters | grep -Fq 'https://hermes-agent.cachix.org'; then
  echo "Nix did not load the Hermes binary cache." >&2
  exit 1
fi
trusted_public_keys=$(nix config show trusted-public-keys)
while IFS= read -r signing_key; do
  [[ -n $signing_key ]] || continue
  if ! printf '%s\n' "$trusted_public_keys" | tr ' ' '\n' | grep -Fxq "$signing_key"; then
    printf 'Nix did not load the CI binary cache signing key: %s\n' "${signing_key%%:*}" >&2
    exit 1
  fi
done < <(sed -n -E 's/^(extra-)?trusted-public-keys = //p' "$repo_root/.github/nix.conf" | tr ' ' '\n')
