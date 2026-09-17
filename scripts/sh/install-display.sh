#!/usr/bin/env bash

# Wrap the whole installer, never a shell function: functions must retain their
# state and errexit semantics. Nested Taskfile adapters share the same PTY.
dotfiles_display_exec() {
  [[ ${DOTFILES_LIVE_DISPLAY:-0} != 1 && -t 0 && -t 1 && -t 2 && ${TERM:-dumb} != dumb && ! ${NO_COLOR+x} ]] || return 0
  local python
  python="$(command -v python3)" || return 0
  # Apple's stub may prompt to install developer tools. Do not invoke it before
  # the existing Apple-tools installation phase has had a chance to run.
  if [[ $python == /usr/bin/python3 ]] && ! /usr/bin/xcode-select -p >/dev/null 2>&1; then
    return 0
  fi
  "$python" -c 'import sys; sys.exit(sys.version_info < (3, 9))' >/dev/null 2>&1 || return 0
  exec "$python" "${BASH_SOURCE[0]%/*}/../python/install_display.py" -- "$@"
}

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
  # Native progress and prompts may finish without a newline. Frame the status
  # independently so the live renderer cannot mistake it for command output.
  if [[ ${DOTFILES_LIVE_DISPLAY:-0} == 1 ]]; then
    printf '\n' >&2
  fi
  printf '%s[DONE] %s\n' "$DOTFILES_DISPLAY_RESET" "$phase" >&2
  DOTFILES_DISPLAY_PHASE=''
}
