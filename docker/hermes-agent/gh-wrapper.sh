#!/usr/bin/env sh
set -eu

if [ -z "${GH_TOKEN:-}" ] && [ -n "${GITHUB_PERSONAL_ACCESS_TOKEN:-}" ]; then
  export GH_TOKEN="${GITHUB_PERSONAL_ACCESS_TOKEN}"
fi

if [ -z "${GITHUB_TOKEN:-}" ] && [ -n "${GITHUB_PERSONAL_ACCESS_TOKEN:-}" ]; then
  export GITHUB_TOKEN="${GITHUB_PERSONAL_ACCESS_TOKEN}"
fi

exec /usr/bin/gh "$@"
