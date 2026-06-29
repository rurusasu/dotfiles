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

- account: `my.1password.com`
- vault: `Private`
- item: `Hermes Agent Dashboard`

`Handler.HermesAgent.ps1` は取得した password を Hermes Docker image 内で hash 化し、
`~/.hermes/.env` には username / password hash / secret だけを書く。1Password から取得できた場合は
`~/.hermes/dashboard-basic-auth-password.txt` を残さない。

1Password CLI が未導入または未認証の場合は、install を止めずにローカル credential を生成する。厳密に
1Password 必須にしたい場合は setup option `HermesAgentRequire1Password=true` を使う。

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
