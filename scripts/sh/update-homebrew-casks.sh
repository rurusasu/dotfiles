#!/usr/bin/env bash
set -euo pipefail

ROOT="${DOTFILES_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)}"
BREW_COMMAND="${BREW_COMMAND:-/opt/homebrew/bin/brew}"
NIX_COMMAND="${NIX_COMMAND:-nix}"
SLEEP_COMMAND="${SLEEP_COMMAND:-sleep}"
JQ_COMMAND="${JQ_COMMAND:-jq}"
PGREP_COMMAND="${PGREP_COMMAND:-pgrep}"
OPEN_COMMAND="${OPEN_COMMAND:-open}"
ATTEMPTS="${DOTFILES_CASK_UPDATE_ATTEMPTS:-3}"
BACKOFF_SECONDS="${DOTFILES_CASK_UPDATE_BACKOFF_SECONDS:-2}"
export HOMEBREW_NO_AUTO_UPDATE=1

case "$ATTEMPTS" in
1 | 2 | 3) ;;
*)
  printf '[macos-cask-update] DOTFILES_CASK_UPDATE_ATTEMPTS must be an integer between 1 and 3: %s\n' \
    "$ATTEMPTS" >&2
  exit 2
  ;;
esac

if [[ $BACKOFF_SECONDS != 2 ]]; then
  printf '[macos-cask-update] DOTFILES_CASK_UPDATE_BACKOFF_SECONDS must be 2: %s\n' \
    "$BACKOFF_SECONDS" >&2
  exit 2
fi

temporary_directory="$(mktemp -d)"
cask_file="$temporary_directory/casks"
failure_file="$temporary_directory/failures"
restart_file="$temporary_directory/restart-apps"
: >"$failure_file"
: >"$restart_file"

cleanup() {
  local status=$?
  trap - EXIT
  reopen_apps || true
  rm -rf "$temporary_directory"
  exit "$status"
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

OUTDATED_OUTPUT=""
OUTDATED_STATUS=0

check_outdated() {
  local cask="$1" command_status
  OUTDATED_OUTPUT=""
  OUTDATED_STATUS=0

  if OUTDATED_OUTPUT=$("$BREW_COMMAND" outdated --cask --greedy "$cask"); then
    command_status=0
  else
    command_status=$?
  fi

  if ((command_status == 0)) && [[ -z $OUTDATED_OUTPUT ]]; then
    return
  fi
  if ((command_status <= 1)) && [[ $OUTDATED_OUTPUT == "$cask" ]]; then
    return
  fi

  OUTDATED_STATUS=$command_status
  ((OUTDATED_STATUS != 0)) || OUTDATED_STATUS=1
  printf '[macos-cask-update] failed to check outdated status for %s (status %d)\n' \
    "$cask" "$command_status" >&2
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

record_running_apps() {
  local cask="$1" app_path status app_file
  app_file="$temporary_directory/app-paths"
  if "$BREW_COMMAND" info --cask "$cask" --json=v2 |
    "$JQ_COMMAND" -r '
      .casks[0].artifacts[]?
      | select(has("app"))
      | if has("target") then .target else .app[] | "/Applications/" + . end
    ' >"$app_file"; then
    :
  else
    status=$?
    printf '[macos-cask-update] failed to inspect application artifacts for %s (status %d)\n' \
      "$cask" "$status" >&2
    return "$status"
  fi

  while IFS= read -r app_path || [[ -n $app_path ]]; do
    [[ -n $app_path ]] || continue
    if "$PGREP_COMMAND" -f "$app_path/Contents/" >/dev/null 2>&1; then
      grep -Fxq "$app_path" "$restart_file" || printf '%s\n' "$app_path" >>"$restart_file"
    fi
  done <"$app_file"
}

reopen_apps() {
  local app_path
  while IFS= read -r app_path || [[ -n $app_path ]]; do
    [[ -n $app_path ]] || continue
    "$OPEN_COMMAND" -gj "$app_path" ||
      printf '[macos-cask-update] failed to reopen application: %s\n' "$app_path" >&2
  done <"$restart_file"
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
  check_outdated "$cask"
  if ((OUTDATED_STATUS != 0)); then
    printf '%s\n' "$cask" >>"$failure_file"
    continue
  fi
  [[ -n $OUTDATED_OUTPUT ]] || continue
  if ! record_running_apps "$cask"; then
    printf '%s\n' "$cask" >>"$failure_file"
    continue
  fi
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
  if is_installed "$cask"; then
    check_outdated "$cask"
  else
    OUTDATED_STATUS=0
    OUTDATED_OUTPUT="$cask"
  fi
  if ((OUTDATED_STATUS != 0)) || [[ -n $OUTDATED_OUTPUT ]]; then
    printf '[macos-cask-update] cask did not converge: %s\n' "$cask" >&2
    grep -Fxq "$cask" "$failure_file" || printf '%s\n' "$cask" >>"$failure_file"
  fi
done <"$cask_file"

[[ ! -s $failure_file ]]
