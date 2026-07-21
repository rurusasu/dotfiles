#!/usr/bin/env sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../../../.." && pwd)
image=${HERMES_GH_WRAPPER_IMAGE:-local/hermes-agent-gh-c10-test:latest}
fixture=$(mktemp -d)
data="$fixture/data"
fake_gh="$fixture/fake-gh"
signal_container=
parser_container=

cleanup() {
  if [ -n "$signal_container" ]; then
    docker rm -f "$signal_container" >/dev/null 2>&1 || true
  fi
  if [ -n "$parser_container" ]; then
    docker rm -f "$parser_container" >/dev/null 2>&1 || true
  fi
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

wait_for_file() {
  target=$1
  attempts=0
  while [ ! -e "$target" ]; do
    attempts=$((attempts + 1))
    [ "$attempts" -le 100 ] || fail 'timed out waiting for container fixture'
    sleep 0.05
  done
}

wait_for_container_exit() {
  container_id=$1
  description=$2
  attempts=0
  while [ "$(docker inspect --format '{{.State.Running}}' "$container_id")" = true ]; do
    attempts=$((attempts + 1))
    [ "$attempts" -le 40 ] || fail "$description did not stop after signal"
    sleep 0.05
  done
}

cat >"$fake_gh" <<'EOF'
#!/bin/sh
set -eu
mkdir -p "$GH_WRAPPER_CAPTURE/argv"
printf '%s\n' "${GH_TOKEN-}" >"$GH_WRAPPER_CAPTURE/token"
printf '%s\n' "$#" >"$GH_WRAPPER_CAPTURE/argc"
IFS= read -r children <"/proc/$$/task/$$/children" || children=
printf '%s\n' "$children" >"$GH_WRAPPER_CAPTURE/children"
tr '\000' '\n' <"/proc/$$/cmdline" >"$GH_WRAPPER_CAPTURE/cmdline"
[ ! -e "/proc/$$/fd/3" ] || printf '%s\n' leak >"$GH_WRAPPER_CAPTURE/saved-fd-leak"
[ -z "${GITHUB_PERSONAL_ACCESS_TOKEN-}" ] || printf '%s\n' leak >"$GH_WRAPPER_CAPTURE/fallback-leak"
[ -z "${GITHUB_TOKEN-}" ] || printf '%s\n' leak >"$GH_WRAPPER_CAPTURE/fallback-leak"
index=0
for argument in "$@"; do
  printf '%s' "$argument" >"$GH_WRAPPER_CAPTURE/argv/$index"
  index=$((index + 1))
done
for temporary in /tmp/hermes-gh-wrapper.*; do
  [ ! -e "$temporary" ] || printf '%s\n' leak >"$GH_WRAPPER_CAPTURE/parser-leak"
done
case "${1-}" in
  __exit__)
    exit "$2"
    ;;
  __wait_signal__)
    trap 'exit 143' TERM
    : >"$GH_WRAPPER_CAPTURE/ready"
    while :; do
      sleep 1
    done
    ;;
  __read_stdin__)
    IFS= read -r original_stdin || true
    printf '%s\n' "$original_stdin" >"$GH_WRAPPER_CAPTURE/stdin"
    ;;
esac
EOF
chmod 700 "$fake_gh"

cat >"$fixture/sitecustomize.py" <<'PY'
import os
import time
from pathlib import Path


capture = Path("/opt/data/capture")

if os.environ.get("GH_WRAPPER_TEST_BLOCK_PARSER") == "1":
    original_open = os.open

    def blocking_open(path, flags, *args, **kwargs):
        if os.fspath(path) == "/opt/data" and flags & getattr(os, "O_DIRECTORY", 0):
            capture.mkdir(parents=True, exist_ok=True)
            (capture / "parser-pid").write_text(str(os.getpid()), encoding="ascii")
            children = Path(
                f"/proc/{os.getpid()}/task/{os.getpid()}/children"
            ).read_text(encoding="ascii")
            (capture / "parser-children").write_text(children, encoding="ascii")
            while True:
                time.sleep(1)
        return original_open(path, flags, *args, **kwargs)

    os.open = blocking_open

if os.environ.get("GH_WRAPPER_TEST_SWAP_ANCESTOR") == "1":
    original_open = os.open
    original_lstat = Path.lstat
    swapped = False

    def swap():
        global swapped
        if swapped:
            return
        os.rename("/opt/data/profiles", "/opt/data/profiles-original")
        os.symlink("/opt/data/outside", "/opt/data/profiles")
        swapped = True

    def controlled_open(path, flags, *args, **kwargs):
        descriptor = original_open(path, flags, *args, **kwargs)
        if os.fspath(path) == "/opt/data" and flags & getattr(os, "O_DIRECTORY", 0):
            swap()
        return descriptor

    def controlled_lstat(path):
        metadata = original_lstat(path)
        if os.fspath(path) == "/opt/data/profiles/rick":
            swap()
        return metadata

    os.open = controlled_open
    Path.lstat = controlled_lstat
PY

docker build -t "$image" "$repo_root/docker/hermes-agent" >"$fixture/build.log" 2>&1 ||
  fail 'final image build failed'
docker run --rm --entrypoint sh "$image" -c 'test -x /usr/local/bin/gh' ||
  fail 'final image does not contain an executable gh wrapper'

run_wrapper() {
  hermes_home=$1
  process_token=$2
  shift 2
  docker run --rm -i \
    -v "$data:/opt/data" \
    -v "$fake_gh:/usr/bin/gh:ro" \
    -e "HERMES_HOME=$hermes_home" \
    -e "GH_TOKEN=$process_token" \
    -e 'GITHUB_PERSONAL_ACCESS_TOKEN=' \
    -e 'GITHUB_TOKEN=' \
    -e 'GH_CONFIG_DIR=/opt/data/capture/gh-config' \
    -e 'GH_WRAPPER_CAPTURE=/opt/data/capture' \
    --entrypoint /usr/local/bin/gh \
    "$image" "$@"
}

run_success() {
  if ! run_wrapper "$@" >"$fixture/stdout" 2>"$fixture/stderr"; then
    fail 'wrapper unexpectedly failed'
  fi
  [ ! -s "$fixture/stdout" ] || fail 'success wrote to stdout'
  [ ! -s "$fixture/stderr" ] || fail 'success wrote to stderr'
}

expect_capture() {
  expected_token=$1
  shift
  printf '%s\n' "$expected_token" >"$fixture/expected-token"
  cmp -s "$fixture/expected-token" "$data/capture/token" || fail 'gh received the wrong token'
  [ "$(cat "$data/capture/argc")" -eq "$#" ] || fail 'gh received the wrong argument count'
  index=0
  for expected_argument in "$@"; do
    printf '%s' "$expected_argument" >"$fixture/expected-argument"
    cmp -s "$fixture/expected-argument" "$data/capture/argv/$index" ||
      fail 'gh received the wrong argv'
    index=$((index + 1))
  done
  [ -z "$(cat "$data/capture/children")" ] || fail 'parser child remained when gh executed'
  [ ! -e "$data/capture/parser-leak" ] || fail 'parser temporary path remained when gh executed'
  [ ! -e "$data/capture/saved-fd-leak" ] || fail 'saved stdin fd remained open in gh'
  [ ! -e "$data/capture/fallback-leak" ] || fail 'fallback token variable remained in gh'
  ! grep -F -- "$expected_token" "$data/capture/cmdline" "$fixture/stdout" "$fixture/stderr" \
    >/dev/null 2>&1 || fail 'token appeared in argv or logs'
  [ ! -e "$data/capture/gh-config/hosts.yml" ] || fail 'wrapper created gh hosts.yml'
}

expect_failure() {
  expected_message=$1
  secret_marker=$2
  shift 2
  if run_wrapper "$@" >"$fixture/stdout" 2>"$fixture/stderr"; then
    fail 'wrapper unexpectedly succeeded'
  else
    status=$?
  fi
  [ "$status" -eq 1 ] || fail 'wrapper returned the wrong credential failure status'
  [ ! -s "$fixture/stdout" ] || fail 'failure wrote to stdout'
  [ "$(cat "$fixture/stderr")" = "$expected_message" ] || fail 'wrapper returned the wrong failure message'
  ! grep -F -- "$secret_marker" "$fixture/stdout" "$fixture/stderr" >/dev/null 2>&1 ||
    fail 'failure diagnostics exposed a token'
  [ ! -e "$data/capture/token" ] || fail 'wrapper invoked gh after credential failure'
  [ ! -e "$data/capture/gh-config/hosts.yml" ] || fail 'wrapper created gh hosts.yml'
}

missing_message='GitHub credentials are missing; rerun the Hermes installer.'
invalid_message='GitHub credentials are invalid; rerun the Hermes installer.'

reset_fixture
mkdir -p "$data/profiles/rick"
printf '%s\n' 'GH_TOKEN=active-token' >"$data/profiles/rick/.env"
printf '%s\n' 'GH_TOKEN=root-token' >"$data/.env"
run_success /opt/data/profiles/rick process-token api 'argument with spaces' '' --jq .login
expect_capture process-token api 'argument with spaces' '' --jq .login

reset_fixture
mkdir -p "$data/profiles/rick" "$data/outside/rick" "$data/hooks"
cp "$fixture/sitecustomize.py" "$data/hooks/sitecustomize.py"
printf '%s\n' 'GH_TOKEN=safe-token' >"$data/profiles/rick/.env"
printf '%s\n' 'GH_TOKEN=outside-sentinel-token' >"$data/outside/rick/.env"
printf '%s\n' 'GH_TOKEN=root-token' >"$data/.env"
if docker run --rm \
  -v "$data:/opt/data" \
  -v "$fake_gh:/usr/bin/gh:ro" \
  -e 'HERMES_HOME=/opt/data/profiles/rick' \
  -e 'GH_TOKEN=' \
  -e 'GITHUB_PERSONAL_ACCESS_TOKEN=' \
  -e 'GITHUB_TOKEN=' \
  -e 'PYTHONPATH=/opt/data/hooks' \
  -e 'GH_WRAPPER_TEST_SWAP_ANCESTOR=1' \
  -e 'GH_CONFIG_DIR=/opt/data/capture/gh-config' \
  -e 'GH_WRAPPER_CAPTURE=/opt/data/capture' \
  --entrypoint /usr/local/bin/gh \
  "$image" api /user >"$fixture/stdout" 2>"$fixture/stderr"; then
  fail 'ancestor swap unexpectedly succeeded'
fi
! grep -R -F -- 'outside-sentinel-token' "$data/capture" "$fixture/stdout" "$fixture/stderr" \
  >/dev/null 2>&1 || fail 'ancestor swap read the outside sentinel'
[ "$(cat "$fixture/stderr")" = "$invalid_message" ] || fail 'ancestor swap returned the wrong failure'

reset_fixture
mkdir -p "$data/profiles/rick"
active_token='  active one'"'"'quote=token  '
printf '%s\n' '# ignored comment' 'GH_TOKEN=' >"$data/profiles/rick/.env"
printf 'GITHUB_PERSONAL_ACCESS_TOKEN=%s\n' "$active_token" >>"$data/profiles/rick/.env"
printf '%s\n' 'GH_TOKEN=root-token' >"$data/.env"
run_success /opt/data/profiles/rick '' api /user
expect_capture "$active_token" api /user

reset_fixture
double_quote_token='active one"quote=token'
printf 'GH_TOKEN=%s\n' "$double_quote_token" >"$data/.env"
run_success /opt/data '' api /user
expect_capture "$double_quote_token" api /user

reset_fixture
mkdir -p "$data/profiles/rick"
printf '%s\n' 'GITHUB_TOKEN=root=fallback' >"$data/.env"
run_success /opt/data/profiles/rick '' repo view owner/name
expect_capture root=fallback repo view owner/name

reset_fixture
printf '%s\n' 'GH_TOKEN=preferred' 'GITHUB_PERSONAL_ACCESS_TOKEN=second' 'GITHUB_TOKEN=third' >"$data/.env"
run_success /opt/data '' api /user
expect_capture preferred api /user

reset_fixture
printf '%s\n' 'GH_TOKEN=process-wins' 'GH_TOKEN=duplicate' >"$data/.env"
run_success /opt/data process-token api /user
expect_capture process-token api /user

reset_fixture
printf '%s\n' '$(touch /opt/data/should-not-exist)' 'GH_TOKEN=literal-token' >"$data/.env"
run_success /opt/data '' api /user
expect_capture literal-token api /user
[ ! -e "$data/should-not-exist" ] || fail 'wrapper evaluated an env file line'

reset_fixture
printf '%s\n' 'GH_TOKEN=stdin-token' >"$data/.env"
stdin_sentinel='original stdin survives parser'
if ! printf '%s\n' "$stdin_sentinel" | run_wrapper /opt/data '' __read_stdin__ \
  >"$fixture/stdout" 2>"$fixture/stderr"; then
  fail 'parser-path stdin test unexpectedly failed'
fi
printf '%s\n' "$stdin_sentinel" >"$fixture/expected-stdin"
cmp -s "$fixture/expected-stdin" "$data/capture/stdin" || fail 'wrapper did not restore original stdin'
expect_capture stdin-token __read_stdin__

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
mkfifo "$data/.env"
expect_failure "$invalid_message" fifo-token /opt/data '' api /user

reset_fixture
mkdir "$data/.env"
expect_failure "$invalid_message" special-token /opt/data '' api /user

reset_fixture
printf '%s\n' 'GH_TOKEN=exit-token' >"$data/.env"
if run_wrapper /opt/data '' __exit__ 37 >"$fixture/stdout" 2>"$fixture/stderr"; then
  fail 'gh exit status test unexpectedly succeeded'
else
  status=$?
fi
[ "$status" -eq 37 ] || fail 'wrapper did not preserve gh exit status'
expect_capture exit-token __exit__ 37

reset_fixture
signal_container=$(docker run -d \
  -v "$data:/opt/data" \
  -v "$fake_gh:/usr/bin/gh:ro" \
  -e 'HERMES_HOME=/opt/data' \
  -e 'GH_TOKEN=signal-token' \
  -e 'GITHUB_PERSONAL_ACCESS_TOKEN=' \
  -e 'GITHUB_TOKEN=' \
  -e 'GH_CONFIG_DIR=/opt/data/capture/gh-config' \
  -e 'GH_WRAPPER_CAPTURE=/opt/data/capture' \
  --entrypoint /usr/local/bin/gh \
  "$image" __wait_signal__)
wait_for_file "$data/capture/ready"
docker kill --signal TERM "$signal_container" >/dev/null
wait_for_container_exit "$signal_container" 'gh signal target'
status=$(docker inspect --format '{{.State.ExitCode}}' "$signal_container")
[ "$status" -eq 143 ] || fail 'wrapper did not propagate the gh signal status'
docker rm "$signal_container" >/dev/null
signal_container=

reset_fixture
mkdir -p "$data/hooks"
cp "$fixture/sitecustomize.py" "$data/hooks/sitecustomize.py"
parser_container=$(docker run -d \
  -v "$data:/opt/data" \
  -v "$fake_gh:/usr/bin/gh:ro" \
  -e 'HERMES_HOME=/opt/data' \
  -e 'GH_TOKEN=' \
  -e 'GITHUB_PERSONAL_ACCESS_TOKEN=' \
  -e 'GITHUB_TOKEN=' \
  -e 'PYTHONPATH=/opt/data/hooks' \
  -e 'GH_WRAPPER_TEST_BLOCK_PARSER=1' \
  --entrypoint /usr/local/bin/gh \
  "$image" api /user)
wait_for_file "$data/capture/parser-pid"
docker kill --signal TERM "$parser_container" >/dev/null
wait_for_container_exit "$parser_container" 'parser signal target'
status=$(docker inspect --format '{{.State.ExitCode}}' "$parser_container")
[ "$status" -eq 143 ] || fail "wrapper did not preserve a signal during parsing (status $status)"
[ "$(cat "$data/capture/parser-pid")" -eq 1 ] || fail 'parser did not replace the wrapper process'
[ ! -s "$data/capture/parser-children" ] ||
  fail "parser retained descendant process $(cat "$data/capture/parser-children")"
docker rm "$parser_container" >/dev/null
parser_container=

printf '%s\n' 'test_gh_wrapper: PASS'
