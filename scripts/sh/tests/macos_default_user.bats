#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd -P)"
  STUB_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$STUB_BIN"
  export PATH="$STUB_BIN:$PATH"
  export TEST_LOG="$BATS_TEST_TMPDIR/commands"
  export TEST_CAPTURE="$BATS_TEST_TMPDIR/capture"
  export TEST_CURRENT_USER=k-miki TEST_UPDATE_STATUS=0 TEST_SWITCH_STATUS=0
  cat >"$STUB_BIN/id" <<'EOF'
#!/usr/bin/env bash
[[ "$*" == '-un' ]] || exit 2
printf '%s\n' "$TEST_CURRENT_USER"
EOF
  cat >"$STUB_BIN/nix" <<'EOF'
#!/usr/bin/env bash
printf 'nix %s\n' "$*" >>"$TEST_LOG"
exit "$TEST_UPDATE_STATUS"
EOF
  cat >"$STUB_BIN/sudo" <<'EOF'
#!/usr/bin/env bash
printf 'sudo' >>"$TEST_LOG"
printf ' <%s>' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
while (($#)); do
  if [[ $1 == --flake ]]; then
    wrapper=${2%#macos}
    wrapper=${wrapper#path:}
    printf '%s' "$wrapper" >"$TEST_CAPTURE.path"
    cp "$wrapper/primary-user" "$TEST_CAPTURE.user"
    exit "$TEST_SWITCH_STATUS"
  fi
  shift
done
exit 2
EOF
  chmod +x "$STUB_BIN/"*
}

@test "macOS rebuild passes the invoking account through the flake before sudo" {
  run env USER=unrelated SUDO_USER=unrelated "$REPO_ROOT/scripts/sh/install-macos.sh" --show-trace
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_CAPTURE.user")" = k-miki ]
  grep -Fq -- "flake update --flake $REPO_ROOT" "$TEST_LOG"
  grep -Fq -- "<--override-input> <dotfiles> <$REPO_ROOT>" "$TEST_LOG"
  grep -Fq -- '<--show-trace>' "$TEST_LOG"
  [ ! -e "$(cat "$TEST_CAPTURE.path")" ]
}

@test "macOS rebuild preserves failure status and removes its temporary flake" {
  export TEST_SWITCH_STATUS=42
  run "$REPO_ROOT/scripts/sh/install-macos.sh"
  [ "$status" -eq 42 ]
  [ ! -e "$(cat "$TEST_CAPTURE.path")" ]
}

@test "macOS rebuild does not activate after a flake update failure" {
  export TEST_UPDATE_STATUS=43
  run "$REPO_ROOT/scripts/sh/install-macos.sh"
  [ "$status" -eq 43 ]
  ! grep -q '^sudo' "$TEST_LOG"
}

@test "macOS rebuild rejects root before updating or activating" {
  export TEST_CURRENT_USER=root
  run "$REPO_ROOT/scripts/sh/install-macos.sh"
  [ "$status" -ne 0 ]
  [[ $output == *'without sudo'* ]]
  [ ! -e "$TEST_LOG" ]
}
