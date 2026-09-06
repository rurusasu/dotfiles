#!/bin/sh
set -eu

if [ "$#" -eq 1 ] && [ "$1" = token ]; then
  exit 0
fi

printf 'unsupported acceptance xurl command: %s\n' "${1:-}" >&2
exit 2
