#!/usr/bin/env bash
set -euo pipefail

if [ ! -d tests/bash ]; then
  echo "No bats tests found — skipping"
  exit 0
fi

apt-get install -y -qq --no-install-recommends bats
bats tests/bash/
