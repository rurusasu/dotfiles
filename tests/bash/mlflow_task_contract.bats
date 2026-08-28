#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  command -v task >/dev/null 2>&1 || skip "go-task is unavailable"
  TEST_ROOT="$BATS_TEST_TMPDIR/task-shell"
  export TASK_TEST_PWSH_ARGS="$TEST_ROOT/pwsh-args"

  mkdir -p "$TEST_ROOT/bin"
  cat >"$TEST_ROOT/bin/pwsh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" >"$TASK_TEST_PWSH_ARGS"
EOF
  chmod +x "$TEST_ROOT/bin/pwsh"
}

run_task_command_through_shell() {
  local source_task="$1"
  local command_index="$2"
  local taskfile="$TEST_ROOT/$source_task-$command_index.yml"
  local command

  command="$(ruby -ryaml -e '
    taskfile = YAML.load_file(ARGV.fetch(0))
    puts taskfile.fetch("tasks").fetch(ARGV.fetch(1)).fetch("cmds")[ARGV.fetch(2).to_i].fetch("cmd")
  ' "$REPO_ROOT/taskfiles/mlflow/taskfile.yml" "$source_task" "$command_index")"
  ruby -ryaml -e '
    puts YAML.dump({"version" => "3", "tasks" => {"probe" => {"cmds" => [ARGV.fetch(0)]}}})
  ' "$command" >"$taskfile"

  run env PATH="$TEST_ROOT/bin:$PATH" task --taskfile "$taskfile" probe
  [ "$status" -eq 0 ]
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
  grep -Fq 'docker compose -f {{.MLFLOW_COMPOSE_FILE}} pull mlflow' "$taskfile"
  grep -Fq 'docker compose -f {{.MLFLOW_COMPOSE_FILE}} up -d --force-recreate --remove-orphans --wait mlflow' "$taskfile"
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

@test "Windows PowerShell payloads survive Task's POSIX command layer" {
  run_task_command_through_shell "mlflow:up" 1
  mapfile -t pwsh_args <"$TASK_TEST_PWSH_ARGS"
  [ "${pwsh_args[0]}" = "-NoProfile" ]
  [ "${pwsh_args[1]}" = "-Command" ]
  [ "${pwsh_args[2]}" = 'docker network inspect local-ai-services *> $null; if ($LASTEXITCODE -ne 0) { docker network create local-ai-services }' ]

  run_task_command_through_shell "mlflow:status" 2
  mapfile -t pwsh_args <"$TASK_TEST_PWSH_ARGS"
  [ "${pwsh_args[0]}" = "-NoProfile" ]
  [ "${pwsh_args[1]}" = "-Command" ]
  [ "${pwsh_args[2]}" = 'Get-Content docker/mlflow/endpoints.yml | Select-String "^\s*-\s+name:\s*(\S+)\s*$" | ForEach-Object { $_.Matches[0].Groups[1].Value }' ]
}
