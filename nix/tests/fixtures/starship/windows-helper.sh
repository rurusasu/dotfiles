#!/usr/bin/env bash
set -euo pipefail

wrapper=$1
export HOME="$TMPDIR/home"
mkdir -p "$HOME" "$TMPDIR/first helper" "$TMPDIR/second helper"
export STARSHIP_HELPER_TEST_LOG="$TMPDIR/helper.log"

for name in first second; do
  printf '#!%s\n' "$2" >"$TMPDIR/$name helper/starship.exe"
  cat >>"$TMPDIR/$name helper/starship.exe" <<'HELPER'
printf '%s\0' "$0" "$@" >"$STARSHIP_HELPER_TEST_LOG"
exit "${STARSHIP_HELPER_TEST_EXIT:-0}"
HELPER
  chmod +x "$TMPDIR/$name helper/starship.exe"
done

for shell in bash zsh; do
  if [ "$shell" = bash ]; then
    executable=$2
    init=$3
    args=(--noprofile --norc)
  else
    executable=$4
    init=$5
    args=(-d -f)
  fi

  PATH="$TMPDIR/first helper:$PATH" TERM=xterm-256color \
    "$executable" "${args[@]}" -ic '
      source "$1"
      PATH="$2/second helper:$PATH"
      "$3" "two words" "" "--literal=\$value"
      printf "%s\0" "$2/first helper/starship.exe" "two words" "" "--literal=\$value" >"$2/expected"
      cmp "$STARSHIP_HELPER_TEST_LOG" "$2/expected" || exit 1

      # The cached executable must survive subsequent prompt invocations and PATH changes.
      "$3" cached
      printf "%s\0" "$2/first helper/starship.exe" cached >"$2/expected"
      cmp "$STARSHIP_HELPER_TEST_LOG" "$2/expected" || exit 1

      # Other callers retain PATH lookup and the Windows helper exit status.
      unset DOTFILES_WINDOWS_STARSHIP
      export STARSHIP_HELPER_TEST_EXIT=37
      if "$3" fallback; then result=0; else result=$?; fi
      [ "$result" -eq 37 ] || exit 1
      printf "%s\0" "$2/second helper/starship.exe" fallback >"$2/expected"
      cmp "$STARSHIP_HELPER_TEST_LOG" "$2/expected" || exit 1
    ' starship-helper-test "$init" "$TMPDIR" "$wrapper"
done
