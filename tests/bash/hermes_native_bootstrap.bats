#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  TEST_HOME="$BATS_TEST_TMPDIR/home"
  STUB_BIN="$BATS_TEST_TMPDIR/bin"
  export HERMES_HOME="$TEST_HOME/.hermes"
  export HERMES_BOOTSTRAP_MANIFEST="$HERMES_HOME/bootstrap-manifest.yaml"
  export SECRET_CAPTURE="$BATS_TEST_TMPDIR/secret-payload.jsonl"
  export PATH="$STUB_BIN:/usr/bin:/bin"
  mkdir -p "$HERMES_HOME" "$STUB_BIN"
  : >"$HERMES_BOOTSTRAP_MANIFEST"

  write_stub hermes-bootstrap '
case "${1:-}" in
  secret-plan)
    printf "%s\\n" "{\"schema_version\":1,\"manifest_sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"items\":[{\"key\":\"discord_rick\",\"account\":\"my.1password.com\",\"vault\":\"openclaw\",\"item\":\"Rick\",\"fields\":[{\"canonical_name\":\"bot_token\",\"labels\":[\"bot_token\"]}]}]}"
    ;;
  apply)
    cat >"$SECRET_CAPTURE"
    if [[ ${FAKE_APPLY_STATUS:-0} == 0 ]]; then printf "%s\\n" "{\"status\":\"ok\"}"; fi
    exit "${FAKE_APPLY_STATUS:-0}"
    ;;
  *) exit 64 ;;
esac
'
  write_stub op '
if [[ " $* " == *" read "* ]]; then
  printf "%s\\n" "service-token"
elif [[ " $* " == *" item get Rick "* ]]; then
  [[ ${OP_SERVICE_ACCOUNT_TOKEN:-} == service-token ]]
  printf "%s\\n" "{\"fields\":[{\"label\":\"bot_token\",\"value\":\"private-test-value\"}]}"
else
  exit 64
fi
'
  export DOTFILES_HERMES_BOOTSTRAP_EXECUTABLE="$STUB_BIN/hermes-bootstrap"
  export DOTFILES_HERMES_OP_EXECUTABLE="$STUB_BIN/op"
}

write_stub() {
  local name="$1" body="$2"
  printf '#!/usr/bin/env bash\nset -euo pipefail\n%s\n' "$body" >"$STUB_BIN/$name"
  chmod +x "$STUB_BIN/$name"
}

@test "native bootstrap passes 1Password values to the transactional apply over stdin" {
  run "$REPO_ROOT/scripts/sh/hermes-bootstrap.sh" apply

  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"ok"'* ]]
  grep -Fq 'private-test-value' "$SECRET_CAPTURE"
  ! [[ "$output" == *'private-test-value'* ]]
}

@test "native bootstrap preserves the apply command failure status" {
  export FAKE_APPLY_STATUS=9

  run "$REPO_ROOT/scripts/sh/hermes-bootstrap.sh" apply

  [ "$status" -eq 9 ]
  [[ "$output" != *'private-test-value'* ]]
}
