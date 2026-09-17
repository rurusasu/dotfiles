#!/usr/bin/env bash

# Leave the command's file descriptors untouched: native progress and prompts
# require a real terminal, and installer functions must retain their shell state.
dotfiles_display_init() {
  DOTFILES_DISPLAY_PHASE=''
  DOTFILES_DISPLAY_BOLD=''
  DOTFILES_DISPLAY_DIM=''
  DOTFILES_DISPLAY_RESET=''
  if [[ -t 1 && -t 2 && ${TERM:-dumb} != dumb && ! ${NO_COLOR+x} ]]; then
    DOTFILES_DISPLAY_BOLD=$'\033[1m'
    DOTFILES_DISPLAY_DIM=$'\033[2m'
    DOTFILES_DISPLAY_RESET=$'\033[0m'
  fi
  trap 'dotfiles_display_exit "$?"' EXIT
}

dotfiles_display_exit() {
  local status="$1"
  printf '%s' "${DOTFILES_DISPLAY_RESET:-}" >&2
  if ((status != 0)) && [[ -n ${DOTFILES_DISPLAY_PHASE:-} ]]; then
    printf '\n%s[FAILED] %s (exit %s)%s\n' \
      "${DOTFILES_DISPLAY_BOLD:-}" "$DOTFILES_DISPLAY_PHASE" "$status" "${DOTFILES_DISPLAY_RESET:-}" >&2
    printf 'See the command output above for details. Later steps were not completed.\n' >&2
  fi
}

dotfiles_step() {
  DOTFILES_DISPLAY_PHASE="$1"
  local description="$2" phase="$1" status
  shift 2
  printf '%s\n%s[RUNNING] %s%s\n' "$DOTFILES_DISPLAY_RESET" "$DOTFILES_DISPLAY_BOLD" "$phase" "$DOTFILES_DISPLAY_RESET" >&2
  printf '%s  %s\n' "$DOTFILES_DISPLAY_DIM" "$description" >&2
  "$@"
  status=$?
  ((status == 0)) || return "$status"
  printf '%s[DONE] %s\n' "$DOTFILES_DISPLAY_RESET" "$phase" >&2
  DOTFILES_DISPLAY_PHASE=''
}
