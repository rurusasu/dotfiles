#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "root task listing exposes all public MLflow operator tasks" {
  run task --taskfile "$REPO_ROOT/Taskfile.yml" --list

  [ "$status" -eq 0 ]
  for task_name in mlflow:up mlflow:configure mlflow:down mlflow:status mlflow:logs mlflow:verify; do
    [[ "$output" == *"$task_name"* ]]
  done
}

@test "MLflow taskfile creates the shared network before startup and preserves it on stop" {
  taskfile="$REPO_ROOT/taskfiles/mlflow/taskfile.yml"

  [ -f "$taskfile" ]
  grep -Fq 'docker network inspect local-ai-services >/dev/null 2>&1 || docker network create local-ai-services' "$taskfile"
  grep -Fq 'docker compose -f {{.MLFLOW_COMPOSE_FILE}} up -d --wait mlflow' "$taskfile"
  down_block="$(awk '
    /^  mlflow:down:/ { in_down = 1; next }
    /^  [^[:space:]][^:]*:/ { in_down = 0 }
    in_down { print }
  ' "$taskfile")"
  [[ "$down_block" == *'docker compose -f {{.MLFLOW_COMPOSE_FILE}} stop mlflow'* ]]
  [[ "$down_block" != *'docker compose '*" down"* ]]
  [[ "$down_block" != *'volume rm'* ]]
  [[ "$down_block" != *'network rm'* ]]
}

@test "Hindsight startup declares MLflow startup as a dependency" {
  taskfile="$REPO_ROOT/taskfiles/hindsight/taskfile.yml"

  grep -A8 '^  hindsight:up:' "$taskfile" | grep -Fq 'task: mlflow:up'
}
