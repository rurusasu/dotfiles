#!/usr/bin/env bash
set -euo pipefail

BREW_COMMAND="${BREW_COMMAND:-/opt/homebrew/bin/brew}"

[[ -x $BREW_COMMAND ]] || exit 0
"$BREW_COMMAND" list --cask --versions arc >/dev/null 2>&1 || exit 0
"$BREW_COMMAND" uninstall --cask --zap arc

# Homebrew's zap can leave this protected CloudKit cache when it needs a
# second sudo prompt. Remove only Arc's known cache path after the cask is gone.
ARC_CLOUDKIT_CACHE="$HOME/Library/Caches/CloudKit/company.thebrowser.Browser"
if [[ -e $ARC_CLOUDKIT_CACHE ]]; then
  if ! rm -rf -- "$ARC_CLOUDKIT_CACHE"; then
    printf 'warning: unable to remove protected Arc cache: %s\n' "$ARC_CLOUDKIT_CACHE" >&2
  fi
fi
