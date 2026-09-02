#!/usr/bin/env bash

set -euo pipefail

hermes_docker_die() {
  printf 'Hermes Docker CLI: %s\n' "$1" >&2
  exit 1
}

compose_file="${HERMES_COMPOSE_FILE:-}"
if [[ -z $compose_file ]]; then
  for candidate in \
    "docker/hermes-service/compose.yml" \
    "${HOME}/.dotfiles/docker/hermes-service/compose.yml"; do
    if [[ -f $candidate ]]; then
      compose_file="$candidate"
      break
    fi
  done
fi

[[ -n $compose_file && -f $compose_file ]] ||
  hermes_docker_die "compose file not found; set HERMES_COMPOSE_FILE or run from the dotfiles repository"

if [[ -t 0 && -t 1 ]]; then
  exec docker-compose -f "$compose_file" exec hermes /opt/hermes/bin/hermes "$@"
else
  exec docker-compose -f "$compose_file" exec -T hermes /opt/hermes/bin/hermes "$@"
fi
