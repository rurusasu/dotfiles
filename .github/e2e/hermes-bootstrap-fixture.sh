#!/bin/sh
set -eu

case "${1:-}" in
secret-plan)
  cat <<'JSON'
{"schema_version":1,"manifest_sha256":"0000000000000000000000000000000000000000000000000000000000000000","items":[{"key":"dashboard","account":"my.1password.com","vault":"openclaw","item":"Hermes Agent Dashboard","fields":[{"canonical_name":"username","labels":["username"]},{"canonical_name":"password","labels":["password"]}]},{"key":"github","account":"my.1password.com","vault":"openclaw","item":"GitHubUsedOpenClawPAT","fields":[{"canonical_name":"credential","labels":["credential"]}]},{"key":"google_calendar","account":"my.1password.com","vault":"openclaw","item":"Google Calendar MCP","fields":[{"canonical_name":"oauth_credentials_json","labels":["oauth_credentials_json"]},{"canonical_name":"tokens_json","labels":["tokens_json"]}]},{"key":"xai_grok","account":"my.1password.com","vault":"openclaw","item":"xAI-Grok-Twitter","fields":[{"canonical_name":"api_key","reference":"console/apikey","labels":["apikey"],"environment":["XAI_API_KEY"]}]},{"key":"discord_default","account":"my.1password.com","vault":"openclaw","item":"Master","fields":[{"canonical_name":"bot_token","labels":["DISCORD_BOT_TOKEN"]},{"canonical_name":"allowed_users","labels":["DISCORD_ALLOWED_USERS"]}]},{"key":"discord_rick","account":"my.1password.com","vault":"openclaw","item":"Rick","fields":[{"canonical_name":"bot_token","labels":["DISCORD_BOT_TOKEN"]},{"canonical_name":"allowed_users","labels":["DISCORD_ALLOWED_USERS"]}]},{"key":"discord_hoffman","account":"my.1password.com","vault":"openclaw","item":"Hoffman","fields":[{"canonical_name":"bot_token","labels":["DISCORD_BOT_TOKEN"]},{"canonical_name":"allowed_users","labels":["DISCORD_ALLOWED_USERS"]}]},{"key":"discord_risarisa","account":"my.1password.com","vault":"openclaw","item":"RisaRisa","fields":[{"canonical_name":"bot_token","labels":["DISCORD_BOT_TOKEN"]},{"canonical_name":"allowed_users","labels":["DISCORD_ALLOWED_USERS"]}]},{"key":"discord_nancy","account":"my.1password.com","vault":"openclaw","item":"Nancy","fields":[{"canonical_name":"bot_token","labels":["DISCORD_BOT_TOKEN"]},{"canonical_name":"allowed_users","labels":["DISCORD_ALLOWED_USERS"]}]},{"key":"discord_kuroda","account":"my.1password.com","vault":"openclaw","item":"Kuroda","fields":[{"canonical_name":"bot_token","labels":["DISCORD_BOT_TOKEN"]},{"canonical_name":"allowed_users","labels":["DISCORD_ALLOWED_USERS"]}]},{"key":"discord_shiraishi","account":"my.1password.com","vault":"openclaw","item":"Shiraishi","fields":[{"canonical_name":"bot_token","labels":["DISCORD_BOT_TOKEN"]},{"canonical_name":"allowed_users","labels":["DISCORD_ALLOWED_USERS"]}]}]}
JSON
  ;;
apply)
  awk '
    NR == 1 { header = ($0 == "{\"type\":\"header\",\"schema_version\":1}") }
    index($0, "\"type\":\"item\"") { items++ }
    { last = $0 }
    END {
      exit !(header && items == 11 && NR == 13 && last == "{\"type\":\"end\"}")
    }
  '
  ;;
*)
  printf 'unsupported acceptance bootstrap command: %s\n' "${1:-}" >&2
  exit 2
  ;;
esac
