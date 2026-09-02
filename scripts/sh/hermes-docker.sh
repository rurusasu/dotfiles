#!/usr/bin/env bash

set -euo pipefail

hermes_docker_die() {
  printf 'Hermes Docker CLI: %s\n' "$1" >&2
  exit 1
}

compose_file="${HERMES_COMPOSE_FILE:-${HOME}/.dotfiles/docker/hermes-service/compose.yml}"
if [[ -n ${HERMES_DOCKER_COMPOSE_PLUGIN:-} ]]; then
  compose_command=("$HERMES_DOCKER_COMPOSE_PLUGIN")
else
  compose_command=(docker compose)
fi

[[ -n $compose_file && -f $compose_file ]] ||
  hermes_docker_die "compose file not found; set HERMES_COMPOSE_FILE or run from the dotfiles repository"

if [[ -t 0 && -t 1 ]]; then
  exec "${compose_command[@]}" -f "$compose_file" exec hermes /opt/hermes/bin/hermes "$@"
else
  exec "${compose_command[@]}" -f "$compose_file" exec -T hermes /opt/hermes/bin/hermes "$@"
fi
