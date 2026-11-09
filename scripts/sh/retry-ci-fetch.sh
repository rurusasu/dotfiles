#!/usr/bin/env bash
# Keep completed Nix builds when a source fetch hits a temporary network failure.
set -euo pipefail

if (($# == 0)); then
  printf 'Usage: %s command [argument ...]\n' "$0" >&2
  exit 64
fi

retry_log=$(mktemp)
retry_stdout=$(mktemp)
trap 'rm -f "$retry_log" "$retry_stdout"' EXIT

for retry_attempt in 1 2 3; do
  # Keep JSON and --print-out-paths stdout usable after a recovered attempt.
  # Stderr streams immediately; only successful stdout is published as stdout.
  if { "$@" >"$retry_stdout"; } 2>&1 | tee "$retry_log" >&2; then
    cat "$retry_stdout"
    exit 0
  else
    retry_statuses=("${PIPESTATUS[@]}")
  fi
  # Fail the job if its output could not be logged, even when the command succeeded.
  if ((retry_statuses[1] != 0)); then
    exit "${retry_statuses[1]}"
  fi
  cat "$retry_stdout" >&2
  cat "$retry_stdout" >>"$retry_log"
  retry_status=${retry_statuses[0]}
  if ((retry_attempt == 3 || retry_status >= 128)); then
    exit "$retry_status"
  fi
  if grep -Eq '^[[:space:]]*error:.*unable to download.*https://api\.github\.com/.*HTTP error 429([[:space:]]|$)' "$retry_log"; then
    retry_reason='GitHub download rate limit'
    retry_delay=$((retry_attempt * 60))
  elif grep -Eq 'curl: \(6\) Could not resolve host:' "$retry_log" &&
    grep -Eq 'error: cannot download .+ from any mirror' "$retry_log"; then
    retry_reason='Temporary DNS failure'
    retry_delay=$((retry_attempt * 10))
  else
    exit "$retry_status"
  fi
  printf '%s; retrying in %s seconds (attempt %s of 3).\n' \
    "$retry_reason" "$retry_delay" "$((retry_attempt + 1))" >&2
  sleep "$retry_delay"
done
