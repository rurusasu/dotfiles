#!/usr/bin/env sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../../../.." && pwd)
wrapper="$repo_root/docker/hermes-agent/gh-wrapper.sh"
image=${HERMES_GH_WRAPPER_IMAGE:-local/hermes-agent-gh:latest}
fixture=$(mktemp -d)
data="$fixture/data"
fake_gh="$fixture/fake-gh"

cleanup() {
  rm -rf "$fixture"
}
trap cleanup EXIT HUP INT TERM

fail() {
  printf '%s\n' "test_gh_wrapper: $1" >&2
  exit 1
}

reset_fixture() {
  rm -rf "$data"
  mkdir -p "$data/capture"
}

cat >"$fake_gh" <<'EOF'
#!/bin/sh
set -eu
mkdir -p "$GH_WRAPPER_CAPTURE"
printf '%s\n' "${GH_TOKEN-}" >"$GH_WRAPPER_CAPTURE/token"
printf '%s\n' "$#" >"$GH_WRAPPER_CAPTURE/argc"
: >"$GH_WRAPPER_CAPTURE/argv"
for argument in "$@"; do
  printf '%s\n' "$argument" >>"$GH_WRAPPER_CAPTURE/argv"
done
EOF
chmod 700 "$fake_gh"

run_wrapper() {
  home=$1
  process_token=$2
  shift 2
  docker run --rm --entrypoint sh \
    -v "$data:/opt/data" \
    -v "$wrapper:/usr/local/bin/gh:ro" \
    -v "$fake_gh:/usr/bin/gh:ro" \
    -e "HERMES_HOME=$home" \
    -e "GH_TOKEN=$process_token" \
    -e 'GITHUB_PERSONAL_ACCESS_TOKEN=' \
    -e 'GITHUB_TOKEN=' \
    -e 'GH_CONFIG_DIR=/opt/data/capture/gh-config' \
    -e 'GH_WRAPPER_CAPTURE=/opt/data/capture' \
    "$image" -c 'exec sh /usr/local/bin/gh "$@"' gh-wrapper "$@"
}

expect_capture() {
  expected_token=$1
  shift
  printf '%s\n' "$expected_token" >"$fixture/expected-token"
  printf '%s\n' "$@" >"$fixture/expected-argv"
  cmp -s "$fixture/expected-token" "$data/capture/token" || fail 'gh received the wrong token'
  cmp -s "$fixture/expected-argv" "$data/capture/argv" || fail 'gh received the wrong argv'
  [ "$(cat "$data/capture/argc")" -eq "$#" ] || fail 'gh received the wrong argument count'
  [ ! -e "$data/capture/gh-config/hosts.yml" ] || fail 'wrapper created gh hosts.yml'
}

expect_failure() {
  expected_message=$1
  secret_marker=$2
  shift 2
  if run_wrapper "$@" >"$fixture/stdout" 2>"$fixture/stderr"; then
    fail 'wrapper unexpectedly succeeded'
  fi
  [ ! -s "$fixture/stdout" ] || fail 'failure wrote to stdout'
  [ "$(cat "$fixture/stderr")" = "$expected_message" ] || fail 'wrapper returned the wrong failure message'
  ! grep -F -- "$secret_marker" "$fixture/stdout" "$fixture/stderr" >/dev/null 2>&1 \
    || fail 'failure diagnostics exposed a token'
  [ ! -e "$data/capture/token" ] || fail 'wrapper invoked gh after credential failure'
  [ ! -e "$data/capture/gh-config/hosts.yml" ] || fail 'wrapper created gh hosts.yml'
}

missing_message='GitHub credentials are missing; rerun the Hermes installer.'
invalid_message='GitHub credentials are invalid; rerun the Hermes installer.'

reset_fixture
mkdir -p "$data/profiles/rick"
printf '%s\n' 'GH_TOKEN=active-token' >"$data/profiles/rick/.env"
printf '%s\n' 'GH_TOKEN=root-token' >"$data/.env"
run_wrapper /opt/data/profiles/rick process-token api /user --jq .login
expect_capture process-token api /user --jq .login

reset_fixture
mkdir -p "$data/profiles/rick"
active_token='  active "quoted"=token  '
printf '%s\n' '# ignored comment' 'GH_TOKEN=' >"$data/profiles/rick/.env"
printf 'GITHUB_PERSONAL_ACCESS_TOKEN=%s\n' "$active_token" >>"$data/profiles/rick/.env"
printf '%s\n' 'GH_TOKEN=root-token' >"$data/.env"
run_wrapper /opt/data/profiles/rick '' api /user
expect_capture "$active_token" api /user

reset_fixture
mkdir -p "$data/profiles/rick"
printf '%s\n' 'GITHUB_TOKEN=root=fallback' >"$data/.env"
run_wrapper /opt/data/profiles/rick '' repo view owner/name
expect_capture root=fallback repo view owner/name

reset_fixture
printf '%s\n' 'GH_TOKEN=preferred' 'GITHUB_PERSONAL_ACCESS_TOKEN=second' 'GITHUB_TOKEN=third' >"$data/.env"
run_wrapper /opt/data '' api /user
expect_capture preferred api /user

reset_fixture
printf '%s\n' 'GH_TOKEN=process-wins' 'GH_TOKEN=duplicate' >"$data/.env"
run_wrapper /opt/data process-token api /user
expect_capture process-token api /user

reset_fixture
printf '%s\n' '$(touch /opt/data/should-not-exist)' 'GH_TOKEN=literal-token' >"$data/.env"
run_wrapper /opt/data '' api /user
expect_capture literal-token api /user
[ ! -e "$data/should-not-exist" ] || fail 'wrapper evaluated an env file line'

reset_fixture
expect_failure "$missing_message" root-token /opt/data '' api /user

reset_fixture
printf '%s\n' 'GH_TOKEN=preferred' 'GITHUB_TOKEN=first' 'GITHUB_TOKEN=second' >"$data/.env"
expect_failure "$invalid_message" preferred /opt/data '' api /user

reset_fixture
printf 'GH_TOKEN=bad\000value\n' >"$data/.env"
expect_failure "$invalid_message" bad /opt/data '' api /user

reset_fixture
printf 'GH_TOKEN=bad\377\n' >"$data/.env"
expect_failure "$invalid_message" bad /opt/data '' api /user

reset_fixture
printf '%s\n' 'GH_TOKEN = malformed' >"$data/.env"
expect_failure "$invalid_message" malformed /opt/data '' api /user

reset_fixture
printf '%s\n' 'GH_TOKEN="first' 'second"' >"$data/.env"
expect_failure "$invalid_message" first /opt/data '' api /user

reset_fixture
dd if=/dev/zero of="$data/.env" bs=1024 count=1025 >/dev/null 2>&1
expect_failure "$invalid_message" oversized /opt/data '' api /user

reset_fixture
printf '%s\n' 'GH_TOKEN=root-token' >"$data/real.env"
ln -s real.env "$data/.env"
expect_failure "$invalid_message" root-token /opt/data '' api /user

reset_fixture
printf '%s\n' 'GH_TOKEN=root-token' >"$data/real.env"
ln "$data/real.env" "$data/.env"
expect_failure "$invalid_message" root-token /opt/data '' api /user

reset_fixture
mkdir -p "$data/profiles"
outside="$fixture/outside"
mkdir -p "$outside"
printf '%s\n' 'GH_TOKEN=outside-token' >"$outside/.env"
ln -s "$outside" "$data/profiles/escaped"
printf '%s\n' 'GH_TOKEN=root-token' >"$data/.env"
expect_failure "$invalid_message" outside-token /opt/data/profiles/escaped '' api /user

reset_fixture
outside="$fixture/outside"
mkdir -p "$outside"
printf '%s\n' 'GH_TOKEN=root-token' >"$data/.env"
expect_failure "$invalid_message" root-token "$outside" '' api /user

printf '%s\n' 'test_gh_wrapper: PASS'
