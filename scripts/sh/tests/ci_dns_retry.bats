#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export RETRY_CALLS="$BATS_TEST_TMPDIR/calls"
  export RETRY_SLEEPS="$BATS_TEST_TMPDIR/sleeps"
  export RETRY_FAILURES=0 RETRY_EXIT=23
  export RETRY_ERROR=$'curl: (6) Could not resolve host: example.invalid\nerror: cannot download source.tar.gz from any mirror'
  local stub_bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$stub_bin"
  cat >"$stub_bin/target" <<'EOF'
#!/usr/bin/env bash
attempt=1
if [[ -f "$RETRY_CALLS" ]]; then attempt=$(( $(wc -l < "$RETRY_CALLS") + 1 )); fi
printf '%s\n' "$attempt" >> "$RETRY_CALLS"
if ((attempt <= RETRY_FAILURES)); then
  failure=$RETRY_ERROR
  if ((attempt > 1)); then failure=${RETRY_SECOND_ERROR:-$failure}; fi
  printf '%s\n' "$failure" >&2
  exit "$RETRY_EXIT"
fi
printf 'success: <%s>\n' "$@"
EOF
  cat >"$stub_bin/sleep" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$1" >> "$RETRY_SLEEPS"
EOF
  chmod +x "$stub_bin/target" "$stub_bin/sleep"
  export PATH="$stub_bin:$PATH"
}

@test "CI DNS retry preserves successful command arguments without repeating it" {
  run bash "$REPO_ROOT/scripts/sh/retry-ci-dns.sh" target 'two words' '$(not-a-command)'
  [ "$status" -eq 0 ]
  [[ $output == *'success: <two words>'* ]]
  [[ $output == *'success: <$(not-a-command)>'* ]]
  [ "$(wc -l <"$RETRY_CALLS" | tr -d ' ')" -eq 1 ]
  [ ! -e "$RETRY_SLEEPS" ]
}

@test "CI DNS retry stops after three failed attempts and keeps the exit status" {
  export RETRY_FAILURES=9
  run bash "$REPO_ROOT/scripts/sh/retry-ci-dns.sh" target
  [ "$status" -eq 23 ]
  [ "$(wc -l <"$RETRY_CALLS" | tr -d ' ')" -eq 3 ]
  [ "$(tr '\n' ' ' <"$RETRY_SLEEPS")" = '10 20 ' ]
}

@test "CI DNS retry fails immediately for errors unrelated to DNS" {
  export RETRY_FAILURES=9 RETRY_ERROR='error: invalid configuration' RETRY_EXIT=42
  run bash "$REPO_ROOT/scripts/sh/retry-ci-dns.sh" target
  [ "$status" -eq 42 ]
  [ "$(wc -l <"$RETRY_CALLS" | tr -d ' ')" -eq 1 ]
  [ ! -e "$RETRY_SLEEPS" ]
}

@test "CI DNS retry does not reuse a previous attempt's lookup error" {
  export RETRY_FAILURES=9 RETRY_SECOND_ERROR='error: invalid configuration'
  run bash "$REPO_ROOT/scripts/sh/retry-ci-dns.sh" target
  [ "$status" -eq 23 ]
  [ "$(wc -l <"$RETRY_CALLS" | tr -d ' ')" -eq 2 ]
  [ "$(cat "$RETRY_SLEEPS")" = 10 ]
}

@test "CI DNS retry ignores a recovered lookup error before an unrelated failure" {
  export RETRY_FAILURES=9 RETRY_EXIT=42
  export RETRY_ERROR=$'curl: (6) Could not resolve host: example.invalid\nDownload recovered\nerror: activation failed'
  run bash "$REPO_ROOT/scripts/sh/retry-ci-dns.sh" target
  [ "$status" -eq 42 ]
  [ "$(wc -l <"$RETRY_CALLS" | tr -d ' ')" -eq 1 ]
  [ ! -e "$RETRY_SLEEPS" ]
}

@test "CI DNS retry preserves cancellation without another attempt" {
  export RETRY_FAILURES=9 RETRY_EXIT=130
  run bash "$REPO_ROOT/scripts/sh/retry-ci-dns.sh" target
  [ "$status" -eq 130 ]
  [ "$(wc -l <"$RETRY_CALLS" | tr -d ' ')" -eq 1 ]
  [ ! -e "$RETRY_SLEEPS" ]
}

@test "CI DNS recovery publishes only the successful machine-readable stdout" {
  cat >"$BATS_TEST_TMPDIR/bin/json-target" <<'EOF'
#!/usr/bin/env bash
if [[ ! -e "$RETRY_CALLS" ]]; then
  printf first >"$RETRY_CALLS"
  printf '{"incomplete":\n'
  printf '%s\n' "$RETRY_ERROR" >&2
  exit 23
fi
printf '{"path":"/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-source"}\n'
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/json-target"
  run bash -c 'bash "$1" json-target >"$2"' fixture \
    "$REPO_ROOT/scripts/sh/retry-ci-dns.sh" "$BATS_TEST_TMPDIR/stdout"
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/stdout")" = '{"path":"/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-source"}' ]
  [[ $output == *'incomplete'* ]]
  [ "$(cat "$RETRY_SLEEPS")" = 10 ]
}
