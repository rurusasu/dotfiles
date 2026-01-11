#!/usr/bin/env bash
set -euo pipefail

nix shell \
  nixpkgs#treefmt \
  nixpkgs#nixfmt \
  nixpkgs#shfmt \
  nixpkgs#powershell \
  nixpkgs#taplo \
  nixpkgs#stylua \
  nixpkgs#dprint \
  nixpkgs#nodePackages.prettier \
  --command treefmt "$@"
