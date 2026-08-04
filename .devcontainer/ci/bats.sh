#!/usr/bin/env bash
set -euo pipefail

if [ ! -d tests/bash ]; then
  echo "No bats tests found — skipping"
  exit 0
fi

export PATH="/run/system-manager/sw/bin:/etc/profiles/per-user/${USER:-root}/bin:$HOME/.nix-profile/bin:$HOME/.local/state/nix/profile/bin:$PATH"

apt-get install -y -qq --no-install-recommends bats jq
bats tests/bash/
