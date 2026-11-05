#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
# shellcheck source=scripts/sh/lib/install-options.sh
. "$ROOT/scripts/sh/lib/install-options.sh"
primary_user=$(id -un)
if [[ $primary_user == root ]]; then
  printf 'Run the macOS installer as your login user, without sudo.\n' >&2
  exit 1
fi

if [[ $UPDATE_FLAKE_INPUTS == true ]]; then
  nix --accept-flake-config --extra-experimental-features 'nix-command flakes' \
    flake update --flake "$ROOT"
fi

# A deployment can select the immutable flake produced for this login user.
flake_ref=${DOTFILES_FLAKE_REF:-}
override_options=()
if [[ -z $flake_ref ]]; then
  # shellcheck source=scripts/sh/lib/darwin-flake.sh
  . "$ROOT/scripts/sh/lib/darwin-flake.sh"
  darwin_flake=$(mktemp -d)
  trap 'rm -f "$darwin_flake/flake.nix" "$darwin_flake/flake.lock" "$darwin_flake/primary-user" "$darwin_flake/ci-settings.nix"; rmdir "$darwin_flake"' EXIT
  write_darwin_flake "$darwin_flake" "$primary_user"
  flake_ref="path:$darwin_flake#macos"
  override_options=(--override-input dotfiles "$ROOT")
  if [[ $UPDATE_FLAKE_INPUTS == false ]]; then
    # Creating the temporary wrapper lock does not update the source's lock.
    nix --accept-flake-config --extra-experimental-features 'nix-command flakes' \
      flake lock "path:$darwin_flake" --offline "${override_options[@]}"
  fi
fi

sudo --set-home ${install_sudo_options[@]+"${install_sudo_options[@]}"} "$(command -v nix)" --accept-flake-config \
  --extra-experimental-features 'nix-command flakes' \
  run ${install_flake_options[@]+"${install_flake_options[@]}"} "$ROOT#darwin-rebuild" -- switch --flake "$flake_ref" \
  ${override_options[@]+"${override_options[@]}"} --impure ${install_flake_options[@]+"${install_flake_options[@]}"} \
  --option accept-flake-config true "$@"
