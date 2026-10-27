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

@test "CI DNS retry recovers after a temporary lookup failure" {
  export RETRY_FAILURES=1
  run bash "$REPO_ROOT/scripts/sh/retry-ci-dns.sh" target ready
  [ "$status" -eq 0 ]
  [[ $output == *'success: <ready>'* ]]
  [ "$(wc -l <"$RETRY_CALLS" | tr -d ' ')" -eq 2 ]
  [ "$(cat "$RETRY_SLEEPS")" = 10 ]
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

workflow_step() {
  awk -v target="      - name: $1" '
    $0 == target { found = 1; next }
    found && /^        run: \|$/ { body = 1; next }
    body && /^          / { sub(/^          /, ""); print; next }
    body { exit }
  ' "$REPO_ROOT/.github/workflows/ci-nix.yml"
}

@test "Darwin CI retries the build but activates the built system only once" {
  local build_step apply_step fixture="$BATS_TEST_TMPDIR/repository"
  build_step=$(workflow_step 'Build macOS configuration')
  apply_step=$(workflow_step 'Apply macOS configuration')
  [ -n "$build_step" ]
  [ -n "$apply_step" ]
  export RUNNER_TEMP="$BATS_TEST_TMPDIR/runner" GITHUB_WORKSPACE="$fixture"
  export CI_PHASE_LOG="$BATS_TEST_TMPDIR/phases" CI_SYSTEM="$BATS_TEST_TMPDIR/system"
  mkdir -p "$RUNNER_TEMP" "$fixture/scripts/sh" "$CI_SYSTEM/sw/bin"
  CI_SYSTEM=$(cd "$CI_SYSTEM" && pwd -P)
  cp "$REPO_ROOT/scripts/sh/retry-ci-dns.sh" "$fixture/scripts/sh/"
  cat >"$BATS_TEST_TMPDIR/bin/sudo" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == -H ]]; then shift; fi
exec "$@"
EOF
  cat >"$BATS_TEST_TMPDIR/bin/nix" <<'EOF'
#!/usr/bin/env bash
printf 'build\n' >> "$CI_PHASE_LOG"
if [[ ! -e "$RUNNER_TEMP/downloaded" ]]; then
  touch "$RUNNER_TEMP/downloaded"
  printf '%s\n' 'curl: (6) Could not resolve host: example.invalid' 'error: cannot download source.tar.gz from any mirror' >&2
  exit 1
fi
ln -s "$CI_SYSTEM" "$RUNNER_TEMP/darwin-system"
EOF
  cat >"$BATS_TEST_TMPDIR/bin/nix-env" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == -p && "$2" == /nix/var/nix/profiles/system && "$3" == --set && "$4" == "$CI_SYSTEM" ]] || exit 9
printf 'profile\n' >> "$CI_PHASE_LOG"
EOF
  cat >"$CI_SYSTEM/sw/bin/darwin-rebuild" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == activate ]] || exit 9
printf 'activate\n' >> "$CI_PHASE_LOG"
printf 'error: activation failed\n' >&2
exit 42
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/"* "$CI_SYSTEM/sw/bin/darwin-rebuild"
  printf 'set -euo pipefail\n%s\n%s\n' "$build_step" "$apply_step" >"$BATS_TEST_TMPDIR/workflow.sh"
  cd "$fixture"
  run bash "$BATS_TEST_TMPDIR/workflow.sh"
  [ "$status" -eq 42 ]
  [ "$(tr '\n' ' ' <"$CI_PHASE_LOG")" = 'build build profile activate ' ]
}
