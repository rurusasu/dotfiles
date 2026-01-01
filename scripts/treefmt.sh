#!/usr/bin/env bash
set -euo pipefail

nix shell nixpkgs#treefmt nixpkgs#nixfmt --command treefmt "$@"
