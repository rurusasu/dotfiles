#!/bin/sh
set -eu

case "${1:-}" in
secret-plan)
  cat <<'JSON'
	{"schema_version":1,"items":[{"key":"dashboard","account":"my.1password.com","vault":"openclaw","item":"Hermes Agent Dashboard","fields":[{"canonical_name":"username","labels":["username"]},{"canonical_name":"password","labels":["password"]}]},{"key":"github","account":"my.1password.com","vault":"openclaw","item":"GitHubUsedOpenClawPAT","fields":[{"canonical_name":"credential","labels":["credential"]}]},{"key":"google_calendar","account":"my.1password.com","vault":"Private","item":"Google Calendar MCP","fields":[{"canonical_name":"oauth_credentials_json","labels":["oauth_credentials_json"]},{"canonical_name":"tokens_json","labels":["tokens_json"]}]},{"key":"discord_default","account":"my.1password.com","vault":"openclaw","item":"DiscordBot-OpenClaw","fields":[{"canonical_name":"bot_token","labels":["DISCORD_BOT_TOKEN"]},{"canonical_name":"allowed_users","labels":["DISCORD_ALLOWED_USERS"]}]},{"key":"discord_rick","account":"my.1password.com","vault":"openclaw","item":"DiscordBot-Rick","fields":[{"canonical_name":"bot_token","labels":["DISCORD_BOT_TOKEN"]},{"canonical_name":"allowed_users","labels":["DISCORD_ALLOWED_USERS"]}]},{"key":"discord_hoffman","account":"my.1password.com","vault":"openclaw","item":"DiscordBot-Hoffman","fields":[{"canonical_name":"bot_token","labels":["DISCORD_BOT_TOKEN"]},{"canonical_name":"allowed_users","labels":["DISCORD_ALLOWED_USERS"]}]},{"key":"discord_risarisa","account":"my.1password.com","vault":"openclaw","item":"DiscordBot-RisaRisa","fields":[{"canonical_name":"bot_token","labels":["DISCORD_BOT_TOKEN"]},{"canonical_name":"allowed_users","labels":["DISCORD_ALLOWED_USERS"]}]},{"key":"discord_nancy","account":"my.1password.com","vault":"openclaw","item":"DiscordBot-Nancy","fields":[{"canonical_name":"bot_token","labels":["DISCORD_BOT_TOKEN"]},{"canonical_name":"allowed_users","labels":["DISCORD_ALLOWED_USERS"]}]}]}
JSON
  ;;
apply)
  awk '
		NR == 1 { header = ($0 == "{\"type\":\"header\",\"schema_version\":1}") }
		index($0, "\"type\":\"item\"") { items++ }
		{ last = $0 }
		END {
				exit !(header && items == 8 && NR == 10 && last == "{\"type\":\"end\"}")
		}
	'
  ;;
*)
  printf 'unsupported acceptance bootstrap command: %s\n' "${1:-}" >&2
  exit 2
  ;;
esac
