#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."
shopt -s nullglob
bats_files=(tests/bash/*.bats)
if ((${#bats_files[@]} == 0)); then
  echo 'No Bash test suites found.' >&2
  exit 1
fi

exec env -u DOTFILES_SKIP_FLAKE_UPDATE -u DOTFILES_USER -u DOTFILES_HOME -u SUDO_USER \
  bats --print-output-on-failure "${bats_files[@]}"
