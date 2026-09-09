#!/usr/bin/env bash
set -euo pipefail

owned_bats_files=(
  tests/bash/install_linux.bats
  tests/bash/install_macos.bats
)
for bats_file in "${owned_bats_files[@]}"; do
  if [ ! -f "${bats_file}" ]; then
    echo "Required devcontainer Bats suite is missing: ${bats_file}" >&2
    exit 1
  fi
done

apt-get install -y -qq --no-install-recommends bats jq python3 git
# Installer contracts exercise the real Taskfile, even before Home Manager is applied.
nix --extra-experimental-features 'nix-command flakes' shell \
  --inputs-from path:. nixpkgs#go-task \
  --command bats --print-output-on-failure "${owned_bats_files[@]}"
