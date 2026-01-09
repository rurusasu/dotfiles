#!/usr/bin/env bash
set -euo pipefail

nix shell nixpkgs#treefmt nixpkgs#nixfmt nixpkgs#nodePackages.prettier nixpkgs#shfmt nixpkgs#powershell nixpkgs#taplo nixpkgs#stylua --command treefmt "$@"
