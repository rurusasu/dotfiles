# シークレット管理

この dotfiles では、実シークレットを repository に保存しない。source of truth は
1Password に置き、dotfiles には `op://...` 参照、非秘密設定、取得手順だけを置く。

## 基本方針

1. 実シークレット、token、API key、cookie、pairing token はコミットしない。
2. `chezmoi/*.tmpl` では `onepasswordRead` を呼ばない。
3. 1Password が必要な deploy script は、実行時に `op read --account ...` を呼ぶ。
4. `op read` は timeout 付きにし、失敗時は警告または skip で `chezmoi apply` を止めない。
5. Shell に常時必要な値は `op run --env-file ...` で注入する。
6. 複数 1Password account があるため、`--account` を明示する。

## 配置

- `chezmoi/secret/secrets.env`
  - `op run --env-file` 用。値は `op://...` 参照のみ。
- `chezmoi/secret/env.sh`
  - WSL / Linux の fallback loader。`op inject --account ...` を実行時に呼ぶ。
- `chezmoi/secret/env.ps1`
  - PowerShell 用。通常は WezTerm launcher から注入済みの環境変数を受け取り、未設定なら timeout 付きで `op inject --account ...` を呼ぶ。
- `chezmoi/.chezmoidata/mcp_servers.yaml`
  - MCP の `op_env` 参照を置く。client template は失敗しても env fallback を使う。
- `chezmoi/.chezmoiscripts/**`
  - どうしてもファイル配置が必要なものだけ、runtime `op read --account ...` で取得する。

## OpenClaw

OpenClaw は local state に pairing 情報と device token を持つ。これらは端末ごとに承認されるため、
dotfiles へ実体を保存しない。

dotfiles 側で管理するもの:

- `agents.defaults.workspace`
- `browser.enabled`
- 再セットアップ時の手順

1Password 側へ控えてよいもの:

- Gateway token: `op://openclaw/openclaw/gateway token`
- OpenClaw 用 provider API keys
  - `op://openclaw/ExaUsedOpenclawPAT/credential`
  - `op://openclaw/TavilyUsedOpenclawPAT/credential`
  - `op://openclaw/FirecrawlUsedOpenclawPAT/credential`

新しい端末、初期化後、または browser scope が追加された後は、端末ごとに pairing / scope
upgrade を承認する。

```powershell
openclaw devices list
openclaw devices approve <requestId>
openclaw browser status
openclaw browser start
openclaw browser open https://example.com
openclaw browser snapshot
```

`openclaw devices approve --latest` は最新 request を表示して明示コマンドを案内する確認用として扱う。
承認は表示された requestId を `openclaw devices approve <requestId>` で実行する。

## Hermes Agent

Hermes Agent dashboard の Basic Auth は install 時に 1Password から取得する。

Hermes home は Git-managed profile distribution として扱う。root home と profile home の分割ルールは
`docs/hermes-agent/profile-home-layout.md` を参照する。install handler は runtime root 側にも
`/opt/data/docs/profile-home-layout.md` を配置し、managed profile gateway は root `docs` directory を
`/opt/data/docs` に read-only mount する。
root home repository では nested profile repository を混ぜないため `profiles/` を `.gitignore` に追加する。

- account: `my.1password.com`
- vault: `openclaw`
- item: `Hermes Agent Dashboard`

`Handler.HermesAgent.ps1` は取得した password を Hermes Docker image 内で hash 化し、
`~/.hermes/.env` には username / password hash / secret だけを書く。1Password から取得できた場合は
`~/.hermes/dashboard-basic-auth-password.txt` を残さない。

1Password CLI が未導入または未認証の場合は、install を止めずにローカル credential を生成する。厳密に
1Password 必須にしたい場合は setup option `HermesAgentRequire1Password=true` を使う。
managed profile gateway 用には root `.env` の dashboard auth 3キーを各 profile `.env` に同期する。

Hermes Agent Slack integration も install 時に 1Password から取得する。

- account: `my.1password.com`
- vault: `openclaw`
- item: `SlackBot-OpenClaw`
- fields:
  - `bot_token` -> `SLACK_BOT_TOKEN`
  - `app_level_token` -> `SLACK_APP_TOKEN`
  - `SLACK_ALLOWED_USERS` -> `SLACK_ALLOWED_USERS`

`SLACK_ALLOWED_USERS` は Slack の Member ID を comma-separated で置く。未設定の場合、Hermes gateway は安全側で
Slack メッセージを拒否する。
Hermes setup は `slack.require_mention: true`、`slack.strict_mention: false`、`slack.allow_bots: mentions` を root と managed profile の `config.yaml` に設定する。
そのため Slack channel の新規会話では明示的な bot mention を要求し、mention された thread 内では同じ agent への follow-up に再 mention を要求しない。
bot message は、その agent が明示的に mention された場合だけ処理する。

専用 profile を Slack から使う場合は、default gateway と別の Slack app/bot token を使う。

- profile env: `~/.hermes/profiles/researcher/.env`
- 1Password item: `SlackBot-Researcher`
- managed profile 用の 1Password item は `SlackBot-<Profile>` 形式にする
  - `SlackBot-Rick`
  - `SlackBot-Hoffman`
  - `SlackBot-Risarisa`
- fields:
  - `bot_token` -> `SLACK_BOT_TOKEN`
  - `app_level_token` -> `SLACK_APP_TOKEN`
  - `SLACK_ALLOWED_USERS` -> `SLACK_ALLOWED_USERS`

profile 作成直後の `.env` は default profile から clone されることがあるため、専用 Slack token に差し替える前に
profile gateway を起動しない。default と profile gateway が同じ Slack token を待ち受けると、同じ Slack event に二重応答する。
Slack 専用 profile には clone 由来の `TELEGRAM_BOT_TOKEN` など他 platform token を残さない。

専用 gateway は Docker Compose の別 service として起動する。host ports は default と衝突しないように分ける。
Docker service は `profiles/<profile>` を `/opt/data` として mount し、default home の gateway state や supervised process を拾わない。
各 profile gateway は、その profile home 内の `.env` と `auth.json` だけを見る。Slack token、dashboard auth、model provider auth は
profile ごとにローカル provision し、Git には載せない。

```powershell
task hermes:researcher:up
task hermes:researcher:logs
task hermes:researcher:down
task hermes:rick:up
task hermes:hoffman:up
task hermes:risarisa:up
```

- container: `hermes-researcher`
- profile: `researcher`
- API: `http://127.0.0.1:8643`
- dashboard: `http://127.0.0.1:9120`
- container: `hermes-rick`
- profile: `rick`
- API: `http://127.0.0.1:8644`
- dashboard: `http://127.0.0.1:9121`
- container: `hermes-hoffman`
- profile: `hoffman`
- API: `http://127.0.0.1:8645`
- dashboard: `http://127.0.0.1:9122`
- container: `hermes-risarisa`
- profile: `risarisa`
- API: `http://127.0.0.1:8646`
- dashboard: `http://127.0.0.1:9123`

Slack app manifest は次のように researcher profile で生成する。

```powershell
docker exec hermes /opt/hermes/bin/hermes -p researcher slack manifest --write /opt/data/profiles/researcher/slack-manifest.json --name Researcher
```

Hermes Agent の API / MCP 用 token も同じ `openclaw` vault から `~/.hermes/.env` と managed profile の `.env` に同期する。
値は `.env` にだけ書き、`config.yaml` には `${...}` 参照だけを置く。

- `GitHubUsedOpenClawPAT` `credential` -> `GITHUB_TOKEN`, `GH_TOKEN`, `GITHUB_PERSONAL_ACCESS_TOKEN`
- `openclaw` `gateway token` -> `OPENCLAW_GATEWAY_TOKEN`
- `ExaUsedOpenclawPAT` `credential` -> `EXA_API_KEY`
- `TavilyUsedOpenclawPAT` `credential` -> `TAVILY_API_KEY`
- `FirecrawlUsedOpenclawPAT` `credential` -> `FIRECRAWL_API_KEY`
- `OpenClawGeminiAPI` `credential` -> `GEMINI_API_KEY`, `GOOGLE_API_KEY`
- `HuggingFace` `PAT` -> `HF_TOKEN`, `HUGGINGFACEHUB_API_TOKEN`
- `TelegramBot` `credential` -> `TELEGRAM_BOT_TOKEN`
- `XUsedOpenClaw` `credential` -> `XAI_API_KEY`
- `AutoCLI` `credential` -> `AUTOCLI_API_KEY`
- `XApiMcp` `CLIENT_ID` -> `X_API_CLIENT_ID`
- `XApiMcp` `CLIENT_SECRET` -> `X_API_CLIENT_SECRET`

GitHub 操作用には Hermes container 内の `gh` CLI を使う。`gh` は `GH_TOKEN` / `GITHUB_TOKEN` を
参照するため、token を rotate した場合は 1Password 側を更新して Hermes setup を再実行する。
`mcp_servers.github` は重複するため Hermes setup で削除する。

X API MCP は `xurl` bridge を使う。Hermes setup は `mcp_servers.xapi` と `mcp_servers.x-docs` を
`~/.hermes/config.yaml` に生成し、`xurl` の OAuth cache は `~/.hermes/.xurl` に永続化する。
初回 OAuth は X app の redirect URI に `http://localhost:8080/callback` を登録してから実行する。

Hermes Agent から OpenAI Codex provider を使う場合は、Codex CLI の `~/.codex/auth.json` をコピーしない。
refresh token の競合を避けるため、Hermes 側で別 OAuth session を作る。

```powershell
docker exec -it hermes hermes auth add openai-codex
```

## パターン

PowerShell deploy script で値を取得する場合:

```powershell
$account = "EJLA3HRAVZBCXIQ7SRSFGQBTNU"
$secretRef = "op://Private/Example/credential"
op read --account $account $secretRef
```

Shell 起動時に環境変数として渡す場合:

```powershell
op run --env-file="$env:USERPROFILE\.config\shell\secrets.env" -- pwsh
```

## 検証

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts/powershell/tests/Invoke-Tests.ps1 -Path scripts/powershell/tests/chezmoi/ChezmoiTemplate.Tests.ps1
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts/powershell/tests/Invoke-Tests.ps1 -Path scripts/powershell/tests/chezmoi/OpenClawWorkspace.Tests.ps1
```
