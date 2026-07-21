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

Hermes bootstrap requires all six declared 1Password items from account
`my.1password.com`, vault `openclaw`: `Hermes Agent Dashboard`,
`GitHubUsedOpenClawPAT`, `SlackBot-OpenClaw`, `SlackBot-Rick`,
`SlackBot-Hoffman`, and `SlackBot-Risarisa`. It does not create dashboard,
Slack, or GitHub fallback credentials. See
[Hermes Bootstrap Operations](../hermes-agent/bootstrap.md) for the item and
field-label contract.

The host adapter streams each full item JSON object directly to
`hermes-bootstrap`; only the container interprets or persists fields.
`GitHubUsedOpenClawPAT` is mandatory. Its `credential` field is written to the
root and every managed Hermes profile `.env` as `GH_TOKEN`,
`GITHUB_PERSONAL_ACCESS_TOKEN`, and `GITHUB_TOKEN`.
`docker/hermes-agent/gh-wrapper.sh` resolves those keys for the active profile,
falls back to root only when needed, and never creates a separate `gh`
credential store.

Each Slack item (`SlackBot-OpenClaw`, `SlackBot-Rick`, `SlackBot-Hoffman`, and
`SlackBot-Risarisa`) supplies the target profile's Slack fields. The dashboard
item is shared as required by the bootstrap manifest. Values stay in runtime
`.env` files with mode `0600`, never in source distributions or repository
logs.

Slack app registration or rotation through Hermes Browser MCP follows one
strict rule: Browser MCP や tool output に token 値を戻さない。Use noVNC or another
approved non-logged secret channel to save generated values in the matching
`SlackBot-<ProfileTitle>` 1Password item, then rerun bootstrap. Browser-driven
setup does not write runtime credentials directly; without an approved secret
channel, profile の `.env` を変更しない。

The runtime root is `/opt/data`; named profile homes are official distribution
targets, not Git repositories. The canonical shared repository is
`/opt/data/shared/lifelog`; `/opt/data/core/lifelog` is compatibility-only.
Browser lifecycle and source-owned MCP configuration are described in
[Hermes Browser MCP](../hermes-agent/browser-mcp.md).

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
