#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	HINDSIGHT_COMPOSE="$REPO_ROOT/docker/hindsight/compose.yml"
	HERMES_COMPOSE="$REPO_ROOT/docker/hermes-agent/compose.yml"
}

@test "Hindsight has an independent loopback-only Compose project" {
	[ -f "$HINDSIGHT_COMPOSE" ]
	grep -q '^name: hindsight$' "$HINDSIGHT_COMPOSE"
	grep -q '^  hindsight:$' "$HINDSIGHT_COMPOSE"
	grep -q '127.0.0.1:${HINDSIGHT_API_PORT:-8888}:8888' "$HINDSIGHT_COMPOSE"
	grep -q '127.0.0.1:${HINDSIGHT_UI_PORT:-9999}:9999' "$HINDSIGHT_COMPOSE"
	grep -q 'HINDSIGHT_DATA_DIR' "$HINDSIGHT_COMPOSE"
	grep -q 'name: dotfiles-memory' "$HINDSIGHT_COMPOSE"
}

@test "Hermes joins the shared memory network without owning Hindsight" {
	! grep -q '^  hindsight:$' "$HERMES_COMPOSE"
	grep -q 'name: dotfiles-memory' "$HERMES_COMPOSE"
	grep -q 'external: true' "$HERMES_COMPOSE"
	! grep -q 'HERMES_DATA_DIR.*hindsight' "$HERMES_COMPOSE"
}

@test "Task exposes an independent Hindsight lifecycle" {
	grep -q 'hindsight:' "$REPO_ROOT/Taskfile.yml"
	for task_name in up down status logs verify; do
		grep -q "^  hindsight:${task_name}:" "$REPO_ROOT/taskfiles/hindsight/taskfile.yml"
	done
}

@test "Hermes adapters do not start or prepare Hindsight" {
	! grep -q 'dotfiles_hermes_hindsight_prepare_host' "$REPO_ROOT/scripts/sh/hermes-agent.sh"
	! grep -q 'dotfiles_hermes_hindsight_start' "$REPO_ROOT/scripts/sh/hermes-agent.sh"
	! grep -q 'Initialize-HermesHindsightHost' "$REPO_ROOT/scripts/powershell/handlers/Handler.HermesAgent.ps1"
	! grep -q "@('up', '-d', 'hindsight')" "$REPO_ROOT/scripts/powershell/handlers/Handler.HermesAgent.ps1"
}

@test "Windows installs Hindsight in its own handler before Hermes" {
	hindsight_handler="$REPO_ROOT/scripts/powershell/handlers/Handler.Hindsight.ps1"
	hermes_handler="$REPO_ROOT/scripts/powershell/handlers/Handler.HermesAgent.ps1"
	grep -q "Name = 'Hindsight'" "$hindsight_handler"
	grep -q 'Order = 55' "$hindsight_handler"
	grep -q "WithHindsight" "$hindsight_handler"
	! grep -q 'docker\\hindsight\|hindsight.ps1' "$hermes_handler"
}

@test "Codex hooks use the official Hindsight integration with one shared bank" {
	hooks="$REPO_ROOT/chezmoi/dot_codex/hooks.json.tmpl"
	config="$REPO_ROOT/chezmoi/dot_hindsight/codex.json"
	for event in SessionStart UserPromptSubmit Stop; do
		grep -q "\"${event}\"" "$hooks"
	done
	grep -q '/.hindsight/codex/scripts/session_start.py' "$hooks"
	grep -q '/.hindsight/codex/scripts/recall.py' "$hooks"
	grep -q '/.hindsight/codex/scripts/retain.py' "$hooks"
	grep -q '"hindsightApiUrl": "http://127.0.0.1:8888"' "$config"
	grep -q '"bankId": "codex-shared"' "$config"
	grep -q '"upgradeNotice": false' "$config"
}

@test "vendored Codex hooks record their upstream revision" {
	provenance="$REPO_ROOT/chezmoi/dot_hindsight/codex/UPSTREAM.md"
	grep -q 'vectorize-io/hindsight' "$provenance"
	grep -q '3a399343b377b13324e880261ee9ac5ae96dddcd' "$provenance"
}
