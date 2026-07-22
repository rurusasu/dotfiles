#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="${DOTFILES_ACCEPTANCE_REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd -P)}"
FIXTURE_ROOT="${DOTFILES_ACCEPTANCE_FIXTURE_ROOT:-$SCRIPT_DIR}"
CANONICAL_DIR="$REPO_ROOT/docker/hermes-agent"

[[ -x $REPO_ROOT/install.sh ]] || {
  printf 'acceptance installer is missing: %s\n' "$REPO_ROOT/install.sh" >&2
  exit 1
}

install -m 0644 "$FIXTURE_ROOT/bootstrap-compose.yml" "$CANONICAL_DIR/compose.yml"
install -m 0755 "$FIXTURE_ROOT/hermes-bootstrap-fixture.sh" \
  "$CANONICAL_DIR/hermes-bootstrap-fixture.sh"

export DOTFILES_ACCEPTANCE_REPO_ROOT="$REPO_ROOT"
export DOTFILES_ACCEPTANCE_FIXTURE_ROOT="$FIXTURE_ROOT"
export PATH="$FIXTURE_ROOT/bin:$PATH"

exec "$REPO_ROOT/install.sh" "$@"
