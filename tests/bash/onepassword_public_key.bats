#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  script="$REPO_ROOT/nix/modules/1password/sync-ssh-public-key.sh"
  destination="$BATS_TEST_TMPDIR/home/.ssh/signing_key.pub"
  export MOCK_KEY="$BATS_TEST_TMPDIR/fixture.pub"
  export MOCK_OP_ARGS="$BATS_TEST_TMPDIR/op-args"
  export MOCK_OP_MODE=success
  export WSL_DISTRO_NAME=
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  ssh-keygen -q -t ed25519 -N '' -C fixture -f "$BATS_TEST_TMPDIR/fixture"
  # Expand these variables only when the fake CLI runs, not during setup.
  # shellcheck disable=SC2016
  printf '%s\n' '#!/usr/bin/env bash' \
    'printf "%s\n" "$@" > "$MOCK_OP_ARGS"' \
    'case "$MOCK_OP_MODE" in' \
    'failure) exit 1 ;;' \
    'timeout) exec sleep 10 ;;' \
    'invalid) printf "%s\n" "-----BEGIN OPENSSH PRIVATE KEY-----" ;;' \
    'malformed) printf "%s\n" "ssh-ed25519 invalid" ;;' \
    'crlf) sed "s/$/\r/" "$MOCK_KEY" ;;' \
    '*) cat "$MOCK_KEY" ;;' \
    'esac' > "$BATS_TEST_TMPDIR/bin/op"
  chmod +x "$BATS_TEST_TMPDIR/bin/op"
  # The module supplies GNU coreutils, including timeout and atomic mv -T.
  PATH="$BATS_TEST_TMPDIR/bin:$(dirname "$(command -v timeout)"):$PATH"
  export PATH
}

@test "1Password public-key activation installs a validated key with an explicit account" {
  run bash "$script" "$destination" fixture-account 'op://Fixture/key/public key' 1
  [ "$status" -eq 0 ]
  cmp "$MOCK_KEY" "$destination"
  [ "$(stat -c '%a' "$destination")" = 644 ]
  [ "$(stat -c '%a' "$(dirname "$destination")")" = 700 ]
  run cat "$MOCK_OP_ARGS"
  [ "$output" = $'read\nop://Fixture/key/public key\n--account\nfixture-account' ]
}

@test "1Password read failure leaves the existing key intact and does not create a fresh key" {
  mkdir -p "$(dirname "$destination")"
  cp "$MOCK_KEY" "$destination"
  run env MOCK_OP_MODE=failure bash "$script" "$destination" fixture-account 'op://Fixture/key/public key' 1
  [ "$status" -eq 0 ]
  [[ $output == *WARNING* ]]
  cmp "$MOCK_KEY" "$destination"
  run env MOCK_OP_MODE=failure bash "$script" "$BATS_TEST_TMPDIR/fresh/signing_key.pub" fixture-account 'op://Fixture/key/public key' 1
  [ "$status" -eq 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/fresh/signing_key.pub" ]
}

@test "1Password invalid field contents cannot replace an existing public key" {
  mkdir -p "$(dirname "$destination")"
  cp "$MOCK_KEY" "$destination"
  for mode in invalid malformed; do
    run env MOCK_OP_MODE="$mode" bash "$script" "$destination" fixture-account 'op://Fixture/key/public key' 1
    [ "$status" -eq 0 ]
    [[ $output == *WARNING* ]]
    cmp "$MOCK_KEY" "$destination"
  done
  [ -z "$(find "$(dirname "$destination")" -name '.signing_key.pub.*' -print)" ]
}

@test "WSL public-key activation uses op.exe without cache and normalizes CRLF" {
  cp "$BATS_TEST_TMPDIR/bin/op" "$BATS_TEST_TMPDIR/bin/op.exe"
  run env WSL_DISTRO_NAME=NixOS MOCK_OP_MODE=crlf bash "$script" "$destination" fixture-account 'op://Fixture/key/public key' 1
  [ "$status" -eq 0 ]
  cmp "$MOCK_KEY" "$destination"
  run head -n 1 "$MOCK_OP_ARGS"
  [ "$output" = '--cache=false' ]
}

@test "1Password public-key read timeout is bounded and preserves the old key" {
  mkdir -p "$(dirname "$destination")"
  cp "$MOCK_KEY" "$destination"
  run env MOCK_OP_MODE=timeout bash "$script" "$destination" fixture-account 'op://Fixture/key/public key' 0.1
  [ "$status" -eq 0 ]
  [[ $output == *'exit 124'* ]]
  cmp "$MOCK_KEY" "$destination"
}
