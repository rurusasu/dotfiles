#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
export DOTFILES_LOG_PREFIX="hermes-desktop-install"
# shellcheck source=/dev/null
. "$ROOT/scripts/sh/install-common.sh"

HERMES_APP_PATH="${DOTFILES_HERMES_APP_PATH:-/Applications/Hermes.app}"
HERMES_CLI_PATH="${DOTFILES_HERMES_CLI_PATH:-$HOME/.local/bin/hermes}"
HERMES_ROOT="${DOTFILES_HERMES_ROOT:-$HOME/.hermes/hermes-agent}"
HERMES_OPEN_COMMAND="${DOTFILES_HERMES_OPEN_COMMAND:-/usr/bin/open}"
HERMES_SETUP_WAIT_ATTEMPTS="${DOTFILES_HERMES_SETUP_WAIT_ATTEMPTS:-900}"
HERMES_CLI_DIR="$(dirname "$HERMES_CLI_PATH")"
export PATH="$HERMES_CLI_DIR:$PATH"

hermes_desktop_executable() {
  local candidate
  for candidate in \
    "$HERMES_ROOT/apps/desktop/release/mac/Hermes.app/Contents/MacOS/Hermes" \
    "$HERMES_ROOT/apps/desktop/release/mac-arm64/Hermes.app/Contents/MacOS/Hermes"; do
    if [[ -x $candidate ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

hermes_desktop_install_is_complete() {
  [[ -x $HERMES_CLI_PATH ]] || return 1
  [[ -f $HERMES_ROOT/.hermes-bootstrap-complete ]] || return 1
  hermes_desktop_executable >/dev/null || return 1
  "$HERMES_CLI_PATH" --version >/dev/null 2>&1
}

launch_official_hermes_setup() {
  local setup_executable="$HERMES_APP_PATH/Contents/MacOS/Hermes-Setup"
  [[ -x $setup_executable ]] ||
    dotfiles_die "Official Hermes setup is unavailable: $setup_executable"

  if [[ $HERMES_OPEN_COMMAND == */* ]]; then
    [[ -x $HERMES_OPEN_COMMAND ]] ||
      dotfiles_die "macOS open command is unavailable: $HERMES_OPEN_COMMAND"
  else
    dotfiles_have "$HERMES_OPEN_COMMAND" ||
      dotfiles_die "macOS open command is unavailable: $HERMES_OPEN_COMMAND"
  fi

  # Git's command-scope config is meaningful only to the process that created
  # it. Desktop setup launches later through LaunchServices, so inheriting the
  # numbered tuple can leak credentials or leave an incomplete tuple that makes
  # every internal git command fail before cloning Hermes.
  dotfiles_unset_git_command_config_environment
  "$HERMES_OPEN_COMMAND" -n "$HERMES_APP_PATH"
}

main() {
  if ! hermes_desktop_install_is_complete; then
    dotfiles_log "Launching the official Hermes Desktop setup. Complete the visible installer window..."
    launch_official_hermes_setup
    dotfiles_wait_for \
      "$HERMES_SETUP_WAIT_ATTEMPTS" \
      "Hermes Desktop setup completion" \
      hermes_desktop_install_is_complete
  fi

  "$HERMES_CLI_PATH" --version >/dev/null
  hermes_desktop_executable >/dev/null
  dotfiles_log "Official Hermes Desktop runtime and CLI are ready."
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
