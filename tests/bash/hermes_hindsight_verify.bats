#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export TEST_ROOT="$BATS_TEST_TMPDIR/runtime"
  export TEST_LOG="$TEST_ROOT/calls.log"
  export HERMES_DATA_DIR="$TEST_ROOT/hermes-data"
  export HERMES_COMPOSE_FILE="$REPO_ROOT/docker/hermes-agent/compose.yml"
  export HINDSIGHT_COMPOSE_FILE="$REPO_ROOT/docker/hindsight/compose.yml"
  export HINDSIGHT_OLLAMA_READY_ATTEMPTS=1
  export HINDSIGHT_OLLAMA_READY_DELAY_SECONDS=0
  export HINDSIGHT_OLLAMA_PROBE_TIMEOUT_SECONDS=2
  export HINDSIGHT_API_READY_ATTEMPTS=1
  export HINDSIGHT_API_READY_DELAY_SECONDS=0
  export HINDSIGHT_API_PROBE_TIMEOUT_SECONDS=2
  export HERMES_ALIVE_RESPONSE=HERMES_ALIVE
  unset FAIL_MATCH

  mkdir -p "$TEST_ROOT/bin" "$HERMES_DATA_DIR/hindsight"
  : >"$TEST_LOG"
  write_state_fixture
  write_fake docker <<'EOF'
printf 'docker %s\n' "$*" >>"$TEST_LOG"
if [[ ${1:-} == container && ${2:-} == inspect && ${*: -1} == hermes-hindsight ]]; then
  exit 1
fi
if [[ -n ${FAIL_MATCH:-} && " $* " == *" $FAIL_MATCH "* ]]; then
  exit 42
fi
if [[ " $* " == *" exec -T hermes hermes chat --quiet -q "* ]]; then
  printf '%s\n' "$HERMES_ALIVE_RESPONSE"
fi
EOF
  write_fake ollama <<'EOF'
printf 'ollama %s\n' "$*" >>"$TEST_LOG"
EOF
  write_fake curl <<'EOF'
printf 'curl %s\n' "$*" >>"$TEST_LOG"
url="${*: -1}"
case "$url" in
  http://127.0.0.1:11434/api/version)
    printf '{"version":"1.0.0"}\n'
    ;;
  http://127.0.0.1:11434/api/tags)
    printf '{"models":[{"name":"qwen3.6:35b"},{"name":"qwen3-embedding:0.6b"}]}\n'
    ;;
  http://127.0.0.1:8888/health)
    printf '{"status":"healthy","database":"connected"}\n'
    ;;
  http://127.0.0.1:8642/health)
    printf '{"status":"ok"}\n'
    ;;
  *)
    printf 'unexpected curl URL: %s\n' "$url" >&2
    exit 90
    ;;
esac
EOF
  export PATH="$TEST_ROOT/bin:$PATH"
}

write_fake() {
  local name="$1"
  shift
  {
    printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail'
    cat
  } >"$TEST_ROOT/bin/$name"
  chmod +x "$TEST_ROOT/bin/$name"
}

write_state_fixture() {
  cat >"$HERMES_DATA_DIR/hindsight/acceptance-state.json" <<'EOF'
{"run_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","banks":{"default":"test-hermes-default-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","rick":"test-hermes-rick-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","hoffman":"test-hermes-hoffman-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","risarisa":"test-hermes-risarisa-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","nancy":"test-hermes-nancy-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","kuroda":"test-hermes-kuroda-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","shiraishi":"test-hermes-shiraishi-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},"sentinels":{},"timings":{"retain":[],"recall":[]}}
EOF
  chmod 600 "$HERMES_DATA_DIR/hindsight/acceptance-state.json"
}

expected_success_log() {
  cat <<EOF
docker compose -f $HERMES_COMPOSE_FILE config --quiet
ollama pull qwen3.6:35b
ollama pull qwen3-embedding:0.6b
docker compose -f $HINDSIGHT_COMPOSE_FILE config --quiet
docker container inspect --format {{.State.Running}} hermes-hindsight
docker compose -f $HINDSIGHT_COMPOSE_FILE up -d hindsight
curl --fail --silent --show-error --max-time 2 http://127.0.0.1:8888/health
docker compose -f $HERMES_COMPOSE_FILE exec -T hermes hermes-hindsight-acceptance probe --api-url http://hindsight:8888 --ollama-url http://host.docker.internal:11434 --strict-probes 20 --timeout 300 --evidence /opt/data/hindsight/acceptance.json
docker compose -f $HERMES_COMPOSE_FILE exec -T hermes hermes-hindsight-acceptance seed --api-url http://hindsight:8888 --profiles default,rick,hoffman,risarisa,nancy,kuroda,shiraishi --timeout 300 --state /opt/data/hindsight/acceptance-state.json
docker compose -f $HINDSIGHT_COMPOSE_FILE restart hindsight
curl --fail --silent --show-error --max-time 2 http://127.0.0.1:8888/health
docker compose -f $HERMES_COMPOSE_FILE exec -T hermes hermes-hindsight-acceptance verify --api-url http://hindsight:8888 --timeout 300 --state /opt/data/hindsight/acceptance-state.json --evidence /opt/data/hindsight/acceptance.json
docker compose -f $HINDSIGHT_COMPOSE_FILE stop hindsight
docker compose -f $HERMES_COMPOSE_FILE exec -T hermes hermes-hindsight-acceptance degraded --api-url http://hindsight:8888 --timeout 5 --state /opt/data/hindsight/acceptance-state.json --evidence /opt/data/hindsight/acceptance.json
docker compose -f $HERMES_COMPOSE_FILE exec -T hermes hermes chat --quiet -q Reply with exactly HERMES_ALIVE and nothing else.
curl --fail --silent --show-error --max-time 5 http://127.0.0.1:8642/health
docker compose -f $HINDSIGHT_COMPOSE_FILE start hindsight
curl --fail --silent --show-error --max-time 2 http://127.0.0.1:8888/health
docker compose -f $HERMES_COMPOSE_FILE exec -T hermes hermes-hindsight-acceptance recovery --api-url http://hindsight:8888 --timeout 300 --state /opt/data/hindsight/acceptance-state.json --evidence /opt/data/hindsight/acceptance.json
docker compose -f $HERMES_COMPOSE_FILE exec -T hermes hermes-hindsight-acceptance cleanup --api-url http://hindsight:8888 --state /opt/data/hindsight/acceptance-state.json --evidence /opt/data/hindsight/acceptance.json
EOF
}

@test "runs all eleven Unix acceptance phases in exact order and cleans up only after recovery" {
  run "$REPO_ROOT/scripts/sh/hermes-hindsight-verify.sh"

  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_LOG")" = "$(expected_success_log)" ]
  recovery_line="$(grep -n "docker compose -f $HINDSIGHT_COMPOSE_FILE start hindsight" "$TEST_LOG" | cut -d: -f1)"
  cleanup_line="$(grep -n 'acceptance cleanup' "$TEST_LOG" | cut -d: -f1)"
  [ "$cleanup_line" -gt "$recovery_line" ]
}

@test "rejects a nonexact one-shot response, restarts Hindsight, and skips cleanup" {
  export HERMES_ALIVE_RESPONSE="HERMES_ALIVE extra"
  before="$(cat "$HERMES_DATA_DIR/hindsight/acceptance-state.json")"

  run "$REPO_ROOT/scripts/sh/hermes-hindsight-verify.sh"

  [ "$status" -ne 0 ]
  [[ "$output" == *"exact HERMES_ALIVE"* ]]
  run grep -q "docker compose -f $HINDSIGHT_COMPOSE_FILE start hindsight" "$TEST_LOG"
  [ "$status" -eq 0 ]
  run grep -q 'acceptance cleanup' "$TEST_LOG"
  [ "$status" -eq 1 ]
  [ "$(cat "$HERMES_DATA_DIR/hindsight/acceptance-state.json")" = "$before" ]
}

@test "stops on the first failed phase and preserves exact failed-run banks" {
  export FAIL_MATCH="hermes-hindsight-acceptance verify"
  before="$(cat "$HERMES_DATA_DIR/hindsight/acceptance-state.json")"

  run "$REPO_ROOT/scripts/sh/hermes-hindsight-verify.sh"

  [ "$status" -eq 42 ]
  grep -q 'acceptance verify' "$TEST_LOG"
  run grep -q 'stop hindsight' "$TEST_LOG"
  [ "$status" -eq 1 ]
  run grep -q 'acceptance cleanup' "$TEST_LOG"
  [ "$status" -eq 1 ]
  [ "$(cat "$HERMES_DATA_DIR/hindsight/acceptance-state.json")" = "$before" ]
  [[ "$before" == *"test-hermes-shiraishi-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"* ]]
}

@test "restarts Hindsight when degraded verification fails after stop" {
  export FAIL_MATCH="hermes-hindsight-acceptance degraded"

  run "$REPO_ROOT/scripts/sh/hermes-hindsight-verify.sh"

  [ "$status" -eq 42 ]
  grep -q "docker compose -f $HINDSIGHT_COMPOSE_FILE stop hindsight" "$TEST_LOG"
  grep -q "docker compose -f $HINDSIGHT_COMPOSE_FILE start hindsight" "$TEST_LOG"
  run grep -q 'acceptance cleanup' "$TEST_LOG"
  [ "$status" -eq 1 ]
}
