#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
primary_user=$(id -un)
if [[ $primary_user == root ]]; then
  printf 'Run the macOS installer as your login user, without sudo.\n' >&2
  exit 1
fi

nix --accept-flake-config --extra-experimental-features 'nix-command flakes' \
  flake update --flake "$ROOT"

# Keep the shared configuration pure and bind this activation to the login user.
darwin_flake=$(mktemp -d)
trap 'rm -f "$darwin_flake/flake.nix" "$darwin_flake/flake.lock" "$darwin_flake/primary-user"; rmdir "$darwin_flake"' EXIT
printf '%s' "$primary_user" >"$darwin_flake/primary-user"
cat >"$darwin_flake/flake.nix" <<'EOF'
{
  # The installer always overrides this input with the local checkout.
  inputs.dotfiles.url = "path:.";
  outputs = { dotfiles, ... }: {
    darwinConfigurations.macos = dotfiles.darwinConfigurations.macos.extendModules {
      modules = [ ({ lib, ... }: {
        system.primaryUser = lib.mkForce (builtins.readFile ./primary-user);
      }) ];
    };
  };
}
EOF

sudo --set-home "$(command -v nix)" --accept-flake-config \
  --extra-experimental-features 'nix-command flakes' \
  run "$ROOT#darwin-rebuild" -- switch --flake "path:$darwin_flake#macos" \
  --override-input dotfiles "$ROOT" --impure \
  --option accept-flake-config true "$@"
