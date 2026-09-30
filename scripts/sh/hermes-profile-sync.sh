#!/usr/bin/env bash

set -euo pipefail

bootstrap_bin="${DOTFILES_HERMES_BOOTSTRAP_EXECUTABLE:-hermes-bootstrap}"
exec "$bootstrap_bin" sync-profiles "$@"
