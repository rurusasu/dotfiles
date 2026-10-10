#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
export DOTFILES_LOG_PREFIX="hermes-desktop-install"
# shellcheck source=/dev/null
. "$ROOT/scripts/sh/install-common.sh"

main() {
  command -v hermes-desktop >/dev/null 2>&1 ||
    dotfiles_die "Home Manager Hermes Desktop package is unavailable: hermes-desktop"
  command -v hermes >/dev/null 2>&1 ||
    dotfiles_die "Nix-managed Hermes Agent CLI is unavailable: hermes"

  hermes --version
  dotfiles_log "Hermes Desktop is installed and the Nix-managed Hermes Agent CLI is ready."
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
