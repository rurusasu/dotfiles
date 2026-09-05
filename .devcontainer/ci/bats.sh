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

apt-get install -y -qq --no-install-recommends bats jq
bats --print-output-on-failure tests/bash/install_linux.bats tests/bash/install_macos.bats
