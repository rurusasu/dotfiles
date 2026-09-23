#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "WSL Taskfile rebuild does not bootstrap a competing Docker Hermes gateway" {
	grep -q '^  nrs:' "$REPO_ROOT/taskfiles/nix/taskfile.yml"
	! grep -q 'task: hermes:bootstrap\|task: hermes:docker:bootstrap' "$REPO_ROOT/taskfiles/nix/taskfile.yml"
}

@test "Docker Compose maps the host gateway for Ollama access" {
  grep -q 'host.docker.internal:host-gateway' "$REPO_ROOT/docker/hermes-service/compose.yml"
}
