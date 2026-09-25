#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
export DOTFILES_LOG_PREFIX="hermes-desktop-install"
# shellcheck source=/dev/null
. "$ROOT/scripts/sh/install-common.sh"

HERMES_APP_PATH="${DOTFILES_HERMES_APP_PATH:-/Applications/Hermes.app}"

main() {
  [[ -f "$HERMES_APP_PATH/Contents/Info.plist" ]] ||
    dotfiles_die "Hermes Desktop is not installed by the nix-darwin cask: $HERMES_APP_PATH"
  command -v hermes >/dev/null 2>&1 ||
    dotfiles_die "Nix-managed Hermes Agent CLI is unavailable: hermes"

  hermes --version
  dotfiles_log "Hermes Desktop is installed and the Nix-managed Hermes Agent CLI is ready."
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
