#!/usr/bin/env bash

set -euo pipefail

hermes_desktop_docker_die() {
  printf 'Hermes Desktop Docker launcher: %s\n' "$1" >&2
  exit 1
}

remote_url='http://127.0.0.1:9119'
desktop_data_dir="${HOME}/Library/Application Support/Hermes"
registry_file="$desktop_data_dir/connections.json"

if ! curl --fail --silent --show-error --max-time 5 "$remote_url/api/health" >/dev/null; then
  hermes_desktop_docker_die "Docker gateway is unavailable at $remote_url; run 'task hermes:up' first"
fi

[[ -f $registry_file ]] ||
  hermes_desktop_docker_die "Desktop remote connection is not configured; open Hermes Settings > Gateway and sign in once"

if ! jq -e --arg url "$remote_url" '
	.primary as $primary
	| any(.connections[]?;
		.id == $primary
		and .kind == "remote"
		and ((.url? | strings | sub("/+$"; "")) == ($url | sub("/+$"; "")))
		and (.authMode == "oauth" or .authMode == "token")
		and (
			.authMode == "oauth"
			or (
				.token? | type == "object"
				and (.encoding | type == "string")
				and (.encoding == "safeStorage" or .encoding == "plain")
				and (.value | type == "string")
				and (.value | length > 0)
			)
		)
	)
' "$registry_file" >/dev/null 2>&1; then
  hermes_desktop_docker_die "Desktop primary remote connection for $remote_url is not configured; open Hermes Settings > Gateway and sign in once"
fi

unset HERMES_DESKTOP_REMOTE_URL HERMES_DESKTOP_REMOTE_TOKEN
command -v hermes-desktop >/dev/null 2>&1 || hermes_desktop_docker_die "hermes-desktop is not installed; apply the WithHermes profile"
exec hermes-desktop "$@"
