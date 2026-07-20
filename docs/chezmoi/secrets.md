# シークレット管理

この dotfiles では、実シークレットを repository に保存しない。source of truth は
1Password に置き、dotfiles には `op://...` 参照、非秘密設定、取得手順だけを置く。

## 基本方針

1. 実シークレット、token、API key、cookie、pairing token はコミットしない。
2. `chezmoi/*.tmpl` では `onepasswordRead` を呼ばない。
3. 1Password が必要な deploy script は、実行時に `op read --account ...` を呼ぶ。
4. `op read` は timeout 付きにし、失敗時は警告または skip で `chezmoi apply` を止めない。
5. Shell / GUI 起動時は既定で `op` を呼ばない。必要な値は明示コマンドの wrapper で runtime 取得する。
6. 複数 1Password account があるため、`--account` を明示する。

OS 別の `op` 実行ルール、Windows の `--cache=false`、WSL の `op.exe` 利用、
SSH Agent / `op-ssh-sign` のパスは [1Password CLI 運用](../1password/README.md) を参照する。

## 配置

- `chezmoi/dot_config/shell/secrets.env`
  - 個人用 1Password account の `op run --env-file` 用。値は `op://...` 参照のみ。GUI eager 起動や `codex.cmd` 直起動で使う。
- `chezmoi/dot_config/shell/secrets-work.env`
  - 会社用 1Password account の `op run --env-file` 用。`devcontainer` vault の work token を置く。
- `chezmoi/dot_config/shell/secret.sh`
  - WSL / Linux の lazy loader。shell 起動時は即 return し、`DOTFILES_FORCE_SECRET_LOAD=1` のときだけ `op read --account ...` を呼ぶ。
- `chezmoi/dot_config/shell/secret.ps1`
  - PowerShell 用。通常の shell / profile 起動では即 return し、`codex` wrapper などが `DOTFILES_FORCE_SECRET_LOAD=1` を付けたときだけ timeout 付きで個別に `op read --account ...` を呼ぶ。
- `chezmoi/dot_local/bin/executable_orca-launch.cmd`
  - Orca 起動用。既定は direct 起動で 1Password prompt を出さない。起動前に既存の `codex-runtime-home\home\auth.json` を Orca managed account として採用し、Orca の Codex account switching が認証済み home を参照できるようにする。`DOTFILES_GUI_EAGER_SECRET_LOAD=1` のときだけ `op run --env-file` を使う。
- `chezmoi/dot_local/bin/executable_op-run-gui-launch.ps1`
  - GUI launcher の opt-in eager secret 用。account 別の `op run --env-file` を timeout 付きで実行し、1Password が locked / unavailable の場合も GUI 本体を token なしで起動する。
- `chezmoi/.chezmoiscripts/run_always_update-orca-shortcut_windows.ps1.tmpl`
  - Orca の Start Menu shortcut を毎回 `orca-launch.cmd` に向け直す。Orca updater が shortcut を直接 `Orca.exe` に戻しても、次回 apply で修復する。
- `chezmoi/.chezmoiscripts/run_always_update-wezterm-shortcut_windows.ps1.tmpl`
  - WezTerm の Start Menu shortcut と既存 taskbar pin を毎回 `wezterm-launch.cmd` に向け直す。launcher は既定で direct 起動し、既存 env があれば `WSLENV` で WSL に渡す。
- `chezmoi/dot_local/bin/executable_codex.cmd`
  - Codex CLI 直起動用。`~/.local/bin` が `WinGet\Links` より PATH の前にあるため、`codex` はこの wrapper を通ってから実体の `codex.exe` を起動する。`login` は OAuth / terminal handshake を壊さないよう `op run` で包まず、実行前に stale な login listener を掃除する。
- `chezmoi/dot_local/bin/executable_stop-stale-codex-login.ps1`
  - Codex OAuth callback port `127.0.0.1:1457` を以前の `codex.exe login` が掴んだまま残った場合だけ、その stale process を停止する。`-AdoptRuntimeCodexAuth` 付きでは runtime home の認証を Orca managed account に登録し、Orca 子プロセスの `codex login` では `-InitializeManagedCodexHomeFromRuntimeAuth` で managed `CODEX_HOME` に `auth.json` を同期して成功扱いにする。`-CleanFailedOrcaHomes` は手動復旧用で、通常の Orca launcher からは呼ばない。
- `chezmoi/.chezmoidata/mcp_servers.yaml`
  - MCP の `op_env` 参照を置く。client template は失敗しても env fallback を使う。
- `chezmoi/.chezmoiscripts/**`
  - どうしてもファイル配置が必要なものだけ、runtime `op read --account ...` で取得する。

Plane MCP の API token は共有された 1Password item を参照する:

- `op://hxgiw3ekjzktxf7hiyf5lyb4hi/fzhjphxau3ila6wlelo5y4ehhe/credential`

Plane MCP / Plane GitHub sync の workspace slug は secret ではないため、`ruru` に固定する。
Plane 初期セットアップ時も workspace slug は `ruru` にする。
Plane install handler は同じ 1Password item の `username` / `password` で初期 admin user を作成し、
`credential` に保存された `plane_api_...` token を MCP / GitHub sync 用に Plane DB へ登録する。
`credential` が未作成の場合は handler が token を生成して同 item へ追加する。

Plane <-> GitHub issue sync は `chezmoi/dot_config/plane-github-sync/config.json.tmpl`
で管理する。GitHub Issues を source of truth にするため、Plane で作られた未リンク work item は
GitHub issue に作成し、GitHub 側で作られた issue は Plane work item として作成する。既存リンクで
両側が変更された場合は GitHub 側を正として Plane に反映する。Plane 側には GitHub issue URL を、
GitHub issue body には復旧用の `plane-github-sync` marker を残す。

GitHub Actions では mock Pester で双方向同期、競合時の GitHub 優先、marker 復旧、CI path filter を検証する。
実 GitHub issue を作る E2E はローカルで明示実行する。

既定の同期対象:

- `dotfiles` -> `rurusasu/dotfiles`
- `article-collector` -> `rurusasu/article-collector`
- `lifelog` -> `rurusasu/lifelog`

## Hermes Agent

Hermes Agent dashboard の Basic Auth は install 時に 1Password から取得する。

Hermes home は Git-managed profile distribution として扱う。root home と profile home の分割ルールは
`docs/hermes-agent/profile-home-layout.md` を参照する。install handler は runtime root 側にも
`/opt/data/docs/profile-home-layout.md` を配置し、managed profile gateway は root `docs` directory を
`/opt/data/docs` に read-only mount する。
root home repository では nested profile repository を混ぜないため `profiles/` を `.gitignore` に追加する。
`HERMES_DATA_DIR` は Hermes home のままにし、lifelog repo には向けない。共有 lifelog core は
`~/.hermes/core/lifelog` に clone / sync し、container 内では `/opt/data/core/lifelog` として全 gateway から
read/write する。root home repository では `core/` を `.gitignore` に追加する。

- account: `my.1password.com`
- vault: `openclaw`
- item: `Hermes Agent Dashboard`

`Handler.HermesAgent.ps1` と `scripts/sh/hermes-agent.sh` は取得した password を Hermes Docker image 内で hash 化し、
`~/.hermes/.env` には username / password hash / secret だけを書く。1Password から取得できた場合は
`~/.hermes/dashboard-basic-auth-password.txt` を残さない。

1Password CLI が未導入または未認証の場合は、install を止めずにローカル credential を生成する。厳密に
1Password 必須にしたい場合は Windows setup option `HermesAgentRequire1Password=true`、shell installer では
`DOTFILES_HERMES_AGENT_REQUIRE_1PASSWORD=1` を使う。
managed profile gateway 用には root `.env` の dashboard auth 3キーを各 profile `.env` に同期する。

Hermes の lifelog sync は root `~/.hermes/.env` の GitHub token を使う。既存の
`GITHUB_PERSONAL_ACCESS_TOKEN` / `GH_TOKEN` / `GITHUB_TOKEN` を優先し、未設定時は install handler が
`my.1password.com` の `Private/GitHubUsedUserPAT` の `credential` を取得して3つの環境変数へ同期する。
1Password取得を必須にする場合は `HermesAgentRequireGitHub=true` を使う。

Hermes Agent Slack integration も install 時に 1Password から取得できる。

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
Hermes setup では Slack token は strict に扱う。root または `HermesAgentManagedProfiles` に含まれる既存 managed profile の
Slack 1Password item が 1 つでも読めない場合、Docker Compose 起動前に失敗させる。

- profile env: `~/.hermes/profiles/risarisa/.env`
- 1Password item: `SlackBot-Risarisa`
- managed profile 用の 1Password item は `SlackBot-<Profile>` 形式にする。profile を増やす場合は
  `HermesAgentManagedProfiles` に profile 名を追加し、同じ命名規則の 1Password item を用意する。
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

Hermes Docker は公式推奨の one-container/many-profiles 構成で起動する。root `hermes` container 内の s6 が
`gateway-<profile>` service を管理し、profile ごとの Slack bot、cron、session、memory は
`~/.hermes/profiles/<profile>` の `HERMES_HOME` に分離される。
同じ `~/.hermes` や `~/.hermes/profiles/<profile>` を別 Hermes gateway container に同時 mount しない。
各 profile gateway は、その profile home 内の `.env` と `auth.json` だけを見る。Slack token、dashboard auth、model provider auth は
profile ごとにローカル provision し、Git には載せない。

```powershell
task hermes:rick:up
task hermes:hoffman:up
task hermes:risarisa:up
```

- container: `hermes`
- profile services: `gateway-risarisa`, `gateway-rick`, `gateway-hoffman`
- root dashboard: `http://127.0.0.1:9119`
- root API: `http://127.0.0.1:8642`

Slack app manifest は次のように risarisa profile で生成する。

```powershell
docker exec hermes /opt/hermes/bin/hermes -p risarisa slack manifest --write /opt/data/profiles/risarisa/slack-manifest.json --name Risarisa
```

Slack app 登録を Hermes Agent に任せる場合は、Hermes Browser MCP で `https://api.slack.com/apps?new_app=1` を開き、profile の `slack-manifest.json` から app を作成する。ログイン、2FA、workspace 選択、consent が必要な場面では `http://127.0.0.1:${HERMES_BROWSER_VIEW_PORT:-6080}` の noVNC viewer で同じ browser session を操作する。生成した `SLACK_BOT_TOKEN` / `SLACK_APP_TOKEN` / `SLACK_ALLOWED_USERS` は Browser MCP や tool output に token 値を戻さない。token reveal / extraction の前に一度止まり、noVNC または承認済みの non-logged secret channel で profile の `.env` または `SlackBot-<ProfileTitle>` 1Password item に保存する。安全な非ログ経路がない場合は profile の `.env` を変更しない。

Hermes setup は `scripts/lifelog_sync.sh` と daily cron job を `~/.hermes` に作成する。
初回 install では compose 起動後に `sh /opt/data/scripts/lifelog_sync.sh --bootstrap` を default gateway で実行し、
`~/.hermes/core/lifelog` を GitHub から復元する。以後は Hermes cron が毎日 `04:20 UTC` に lifelog repo を
`commit -> pull --rebase -> push` で同期する。`.env`、`auth.json`、token、secret、DB、logs、sessions、cache などが
staged された場合は commit / push せず失敗させる。

Hermes setup は `scripts/article_news_slack.sh` と `article-news-slack-post` cron job も作成する。
この job は 2 時間ごと (`0 */2 * * *`) に `article-collector recommend all` を実行し、article fetch と
`ACP_AGENT=codex` による翻訳を有効にする。生成された `translated.md` は
`/opt/data/core/lifelog/0_inbox/article-news/` に保存し、同じ Markdown を `SLACK_BOT_TOKEN` で Slack channel
`C0AJVDKGN6A` に投稿する。必要に応じて `~/.hermes/.env` の `ARTICLE_NEWS_SLACK_CHANNEL`、
`ARTICLE_NEWS_LIMIT`、`ARTICLE_NEWS_ACP_AGENT`、`ARTICLE_NEWS_TRANSLATE_LANG` で上書きする。

X API MCP は `xurl` bridge を使う。Hermes setup は `mcp_servers.xapi` と `mcp_servers.x-docs` を
`~/.hermes/config.yaml` に生成し、`xurl` の OAuth cache は `~/.hermes/.xurl` に永続化する。
初回 OAuth は X app の redirect URI に `http://localhost:8080/callback` を登録してから実行する。

Browser MCP は host browser を使わず、Compose 内の Chromium / Browser MCP container だけを使う。
内部接続 URL、専用 browser profile、起動順は [Hermes Browser MCP](../hermes-agent/browser-mcp.md) を参照する。

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
op --cache=false read --account $account $secretRef
```

Windows 以外の native `op` では `--cache=false` を一般化しない。OS 別の判断は
[1Password CLI 運用](../1password/README.md) に従う。

通常の shell / GUI 起動では `op` を呼ばない。bash / zsh / PowerShell の `codex`
wrapper が `DOTFILES_FORCE_SECRET_LOAD=1` を付けたときだけ、shell loader が
timeout 付きの `op read --account ...` で不足分を読む。

どうしても起動時に個人用 account の環境変数として渡したい場合:

```powershell
op run --account my.1password.com --env-file="$env:USERPROFILE\.config\shell\secrets.env" -- pwsh
```

個人用と会社用の両方を渡す場合は account ごとに `op run` を分けて nest する:

```powershell
op run --account my.1password.com --env-file="$env:USERPROFILE\.config\shell\secrets.env" -- `
  op run --account aimatecoltd.1password.com --env-file="$env:USERPROFILE\.config\shell\secrets-work.env" -- pwsh
```

Orca / WezTerm は既定で direct 起動し、起動だけでは 1Password prompt を出さない。PowerShell profile から読む `secret.ps1` も、`DOTFILES_FORCE_SECRET_LOAD=1` がない限り `op` を呼ばない。Orca は起動前に `stop-stale-codex-login.ps1 -AdoptRuntimeCodexAuth` を実行し、既存の runtime home 認証を Orca managed account として登録する。Orca が子プロセスで `codex login` を呼ぶ場合は `codex.cmd` が managed `CODEX_HOME` へ runtime 認証を同期して成功扱いにする:

```powershell
~\.local\bin\orca-launch.cmd
```

Orca / WezTerm の GUI process に先に env を注入したい場合だけ opt-in する:

```powershell
$env:DOTFILES_GUI_EAGER_SECRET_LOAD = "1"
$env:DOTFILES_OP_RUN_TIMEOUT_SECONDS = "60"
~\.local\bin\orca-launch.cmd
```

Codex CLI を直接起動する場合も、PATH 上の `~\.local\bin\codex.cmd` が同じ env-file injection を行う。`codex login` は例外で、1Password env-file injection を迂回して実体の `codex.exe` を直接起動する。login 前には `stop-stale-codex-login.ps1` を呼び、以前の `codex.exe login` が `127.0.0.1:1457` を掴んだまま残っている場合だけ停止する:

```powershell
codex
```

## 検証

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts/powershell/tests/Invoke-Tests.ps1 -Path scripts/powershell/tests/chezmoi/ChezmoiTemplate.Tests.ps1
```
