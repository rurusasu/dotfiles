#!/usr/bin/env bash
# Shared deployment options; all changes are confined to this process tree.
UPDATE_FLAKE_INPUTS=${UPDATE_FLAKE_INPUTS:-true}
DOTFILES_ALLOW_BUILDS=${DOTFILES_ALLOW_BUILDS:-true}
for option in UPDATE_FLAKE_INPUTS DOTFILES_ALLOW_BUILDS; do
  case ${!option} in
  true | false) ;;
  *)
    printf '%s must be true or false.\n' "$option" >&2
    exit 64
    ;;
  esac
done
export UPDATE_FLAKE_INPUTS DOTFILES_ALLOW_BUILDS

if [[ -n ${DOTFILES_FLAKE_REF:-} ]]; then
  if [[ $DOTFILES_FLAKE_REF != ?*#?* || ${DOTFILES_FLAKE_REF#*#} == *#* || $DOTFILES_FLAKE_REF == *$'\n'* || $DOTFILES_FLAKE_REF == *$'\r'* ]]; then
    printf 'DOTFILES_FLAKE_REF must select a flake target with #.\n' >&2
    exit 64
  fi
fi

install_flake_options=()
if [[ $UPDATE_FLAKE_INPUTS == false ]]; then
  install_flake_options+=(--no-update-lock-file)
fi
install_sudo_options=()
if [[ $DOTFILES_ALLOW_BUILDS == false ]]; then
  # The empty builders setting also rules out compiling on a remote builder.
  export NIX_CONFIG="${NIX_CONFIG:-}
max-jobs = 0
builders =
fallback = false"
fi
if [[ -n ${NIX_CONFIG:-} ]]; then
  # sudo normally removes NIX_CONFIG; preserve it for rebuild and child clients.
  install_sudo_options+=(--preserve-env=NIX_CONFIG)
fi
