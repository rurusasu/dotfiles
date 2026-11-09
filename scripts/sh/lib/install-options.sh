#!/usr/bin/env bash
# Shared deployment options; all changes are confined to this process tree.
DOTFILES_ALLOW_BUILDS=${DOTFILES_ALLOW_BUILDS:-true}
case $DOTFILES_ALLOW_BUILDS in
true | false) ;;
*)
  printf 'DOTFILES_ALLOW_BUILDS must be true or false.\n' >&2
  exit 64
  ;;
esac
export DOTFILES_ALLOW_BUILDS

if [[ -n ${DOTFILES_FLAKE_REF:-} ]]; then
  if [[ $DOTFILES_FLAKE_REF != ?*#?* || ${DOTFILES_FLAKE_REF#*#} == *#* || $DOTFILES_FLAKE_REF == *$'\n'* || $DOTFILES_FLAKE_REF == *$'\r'* ]]; then
    printf 'DOTFILES_FLAKE_REF must select a flake target with #.\n' >&2
    exit 64
  fi
fi

install_flake_options=(--no-update-lock-file)
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
