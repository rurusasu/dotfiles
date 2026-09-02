#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="${DOTFILES_ACCEPTANCE_REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd -P)}"
FIXTURE_ROOT="${DOTFILES_ACCEPTANCE_FIXTURE_ROOT:-$SCRIPT_DIR}"
CANONICAL_DIR="$REPO_ROOT/docker/hermes-service"
HINDSIGHT_DIR="$REPO_ROOT/docker/local-ai-services"

[[ -x $REPO_ROOT/install.sh ]] || {
  printf 'acceptance installer is missing: %s\n' "$REPO_ROOT/install.sh" >&2
  exit 1
}

# The acceptance Compose file deliberately replaces the production service
# image with lightweight fixtures. Build the production image separately so
# Hermes storage seeding still exercises the same helper used in real runs.
# Offline NixOS tests preload a small equivalent image instead.
if [[ -n ${DOTFILES_ACCEPTANCE_PRELOADED_STORAGE_SEED_IMAGE:-} ]]; then
  docker image inspect "$DOTFILES_ACCEPTANCE_PRELOADED_STORAGE_SEED_IMAGE" >/dev/null
else
  docker build -t local/hermes-agent-gh:latest \
    -f "$REPO_ROOT/docker/hermes-agent/Dockerfile" "$REPO_ROOT/docker"
fi

install -m 0644 "$FIXTURE_ROOT/bootstrap-compose.yml" "$CANONICAL_DIR/compose.yml"
install -m 0644 "$FIXTURE_ROOT/hindsight-compose.yml" "$HINDSIGHT_DIR/compose.yml"
install -m 0755 "$FIXTURE_ROOT/hermes-bootstrap-fixture.sh" \
  "$CANONICAL_DIR/hermes-bootstrap-fixture.sh"
install -m 0755 "$FIXTURE_ROOT/hermes-gateway-converge.sh" \
  "$CANONICAL_DIR/hermes-gateway-converge.sh"
install -m 0644 "$FIXTURE_ROOT/hindsight-health.json" \
  "$HINDSIGHT_DIR/hindsight-health.json"

export DOTFILES_ACCEPTANCE_REPO_ROOT="$REPO_ROOT"
export DOTFILES_ACCEPTANCE_FIXTURE_ROOT="$FIXTURE_ROOT"
export DOTFILES_ACCEPTANCE_SKIP_MLFLOW=1
export DOTFILES_ACCEPTANCE_REAL_CURL="${DOTFILES_ACCEPTANCE_REAL_CURL:-$(command -v curl)}"
export DOTFILES_HERMES_OLLAMA_EXECUTABLE="$FIXTURE_ROOT/bin/ollama"
export DOTFILES_HINDSIGHT_OLLAMA_EXECUTABLE="$FIXTURE_ROOT/bin/ollama"
export DOTFILES_HERMES_CURL_EXECUTABLE="$FIXTURE_ROOT/bin/curl"
export DOTFILES_HERMES_OP_EXECUTABLE="$FIXTURE_ROOT/bin/op"
export PATH="$FIXTURE_ROOT/bin:$PATH"

exec "$REPO_ROOT/install.sh" "$@"
