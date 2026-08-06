#!/usr/bin/env bash
set -euo pipefail

ROOT="${DOTFILES_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)}"
BREW_COMMAND="${BREW_COMMAND:-/opt/homebrew/bin/brew}"
NIX_COMMAND="${NIX_COMMAND:-nix}"
SLEEP_COMMAND="${SLEEP_COMMAND:-sleep}"
ATTEMPTS="${DOTFILES_CASK_UPDATE_ATTEMPTS:-3}"
BACKOFF_SECONDS="${DOTFILES_CASK_UPDATE_BACKOFF_SECONDS:-2}"
export HOMEBREW_NO_AUTO_UPDATE=1

temporary_directory="$(mktemp -d)"
cask_file="$temporary_directory/casks"
failure_file="$temporary_directory/failures"
: >"$failure_file"

cleanup() {
  rm -rf "$temporary_directory"
}
trap cleanup EXIT

load_casks() {
  if [[ ${DOTFILES_HOMEBREW_CASKS+x} == x ]]; then
    printf '%s' "$DOTFILES_HOMEBREW_CASKS"
    return
  fi

  "$NIX_COMMAND" eval --impure --raw \
    "$ROOT#darwinConfigurations.macos.config.homebrew.casks" \
    --apply 'casks: builtins.concatStringsSep "\n" (builtins.map (cask: if builtins.isString cask then cask else cask.name) casks)'
}

is_installed() {
  "$BREW_COMMAND" list --cask --versions "$1" >/dev/null 2>&1
}

is_outdated() {
  [[ -n $("$BREW_COMMAND" outdated --cask --greedy "$1") ]]
}

retry_command() {
  local label="$1"
  shift
  local attempt delay
  for ((attempt = 1; attempt <= ATTEMPTS; attempt++)); do
    if "$@"; then
      return 0
    fi
    if ((attempt < ATTEMPTS)); then
      delay=$((BACKOFF_SECONDS * attempt))
      printf '[macos-cask-update] %s failed (attempt %d/%d); retrying in %ds\n' \
        "$label" "$attempt" "$ATTEMPTS" "$delay" >&2
      "$SLEEP_COMMAND" "$delay"
    fi
  done
  printf '[macos-cask-update] %s failed after %d attempts\n' "$label" "$ATTEMPTS" >&2
  return 1
}

load_casks >"$cask_file"
[[ -s $cask_file ]] || {
  printf '[macos-cask-update] evaluated cask list is empty\n' >&2
  exit 1
}

while IFS= read -r cask || [[ -n $cask ]]; do
  [[ -n $cask ]] || continue
  if ! is_installed "$cask"; then
    printf '[macos-cask-update] declared cask is not installed: %s\n' "$cask" >&2
    printf '%s\n' "$cask" >>"$failure_file"
    continue
  fi
  is_outdated "$cask" || continue
  if ! retry_command "fetch $cask" "$BREW_COMMAND" fetch --cask "$cask"; then
    printf '%s\n' "$cask" >>"$failure_file"
    continue
  fi
  if ! retry_command "upgrade $cask" "$BREW_COMMAND" upgrade --cask --greedy "$cask"; then
    printf '%s\n' "$cask" >>"$failure_file"
  fi
done <"$cask_file"

while IFS= read -r cask || [[ -n $cask ]]; do
  [[ -n $cask ]] || continue
  if ! is_installed "$cask" || is_outdated "$cask"; then
    printf '[macos-cask-update] cask did not converge: %s\n' "$cask" >&2
    grep -Fxq "$cask" "$failure_file" || printf '%s\n' "$cask" >>"$failure_file"
  fi
done <"$cask_file"

[[ ! -s $failure_file ]]
