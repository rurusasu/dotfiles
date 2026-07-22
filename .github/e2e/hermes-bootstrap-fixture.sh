#!/bin/sh
set -eu

case "${1:-}" in
secret-plan)
  cat <<'JSON'
{"schema_version":1,"items":[{"key":"dashboard","account":"my.1password.com","vault":"openclaw","item":"Hermes Agent Dashboard","fields":[{"canonical_name":"username","labels":["username"]},{"canonical_name":"password","labels":["password"]}]},{"key":"github","account":"my.1password.com","vault":"openclaw","item":"GitHubUsedOpenClawPAT","fields":[{"canonical_name":"credential","labels":["credential"]}]},{"key":"slack_default","account":"my.1password.com","vault":"openclaw","item":"SlackBot-OpenClaw","fields":[{"canonical_name":"bot_token","labels":["SLACK_BOT_TOKEN"]},{"canonical_name":"app_token","labels":["SLACK_APP_TOKEN"]},{"canonical_name":"allowed_users","labels":["SLACK_ALLOWED_USERS"]}]},{"key":"slack_rick","account":"my.1password.com","vault":"openclaw","item":"SlackBot-Rick","fields":[{"canonical_name":"bot_token","labels":["SLACK_BOT_TOKEN"]},{"canonical_name":"app_token","labels":["SLACK_APP_TOKEN"]},{"canonical_name":"allowed_users","labels":["SLACK_ALLOWED_USERS"]}]},{"key":"slack_hoffman","account":"my.1password.com","vault":"openclaw","item":"SlackBot-Hoffman","fields":[{"canonical_name":"bot_token","labels":["SLACK_BOT_TOKEN"]},{"canonical_name":"app_token","labels":["SLACK_APP_TOKEN"]},{"canonical_name":"allowed_users","labels":["SLACK_ALLOWED_USERS"]}]},{"key":"slack_risarisa","account":"my.1password.com","vault":"openclaw","item":"SlackBot-Risarisa","fields":[{"canonical_name":"bot_token","labels":["SLACK_BOT_TOKEN"]},{"canonical_name":"app_token","labels":["SLACK_APP_TOKEN"]},{"canonical_name":"allowed_users","labels":["SLACK_ALLOWED_USERS"]}]},{"key":"slack_nancy","account":"my.1password.com","vault":"openclaw","item":"SlackBot-Nancy","fields":[{"canonical_name":"bot_token","labels":["SLACK_BOT_TOKEN"]},{"canonical_name":"app_token","labels":["SLACK_APP_TOKEN"]},{"canonical_name":"allowed_users","labels":["SLACK_ALLOWED_USERS"]}]}]}
JSON
  ;;
apply)
  awk '
		NR == 1 { header = ($0 == "{\"type\":\"header\",\"schema_version\":1}") }
		index($0, "\"type\":\"item\"") { items++ }
		{ last = $0 }
		END {
			exit !(header && items == 7 && NR == 9 && last == "{\"type\":\"end\"}")
		}
	'
  ;;
*)
  printf 'unsupported acceptance bootstrap command: %s\n' "${1:-}" >&2
  exit 2
  ;;
esac
