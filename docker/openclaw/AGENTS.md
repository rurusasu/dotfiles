# openclaw Docker: 実装時の必須ルール

このディレクトリは、openclaw (Telegram / Slack AI gateway) を Docker で動かすための構成を管理する。

## 変更時に必ず触るファイル

- `docker/openclaw/Dockerfile`
- `docker/openclaw/docker-compose.yml`
- `docker/openclaw/entrypoint.sh`
- `docker/openclaw/acpx.config.json`
- `docker/openclaw/gemini.settings.json`
- `docker/openclaw/.env`（通常は自動生成。手動編集は最小限）
- `chezmoi/dot_openclaw/openclaw.docker.json.tmpl`（設定の source of truth）

## 起動と再生成の正規フロー

`scripts/powershell/install.user.ps1` (Handler.OpenClaw.ps1) が以下を一括実行する。

1. `chezmoi apply` で設定を展開
2. `.env` を生成（`OPENCLAW_CONFIG_FILE` など。PAT は含めない）
3. 1Password から GitHub PAT を取得し、`~/.openclaw/secrets/github_token` を更新
4. `docker compose up -d --build` で起動

通常の起動・復旧はこのコマンドを使う。

```powershell
pwsh -File scripts/powershell/install.user.ps1
```

## 設定値の流れ（変更影響の把握用）

```text
1Password secret
  -> chezmoi template (dot_openclaw/openclaw.docker.json.tmpl)
  -> ~/.openclaw/openclaw.docker.json
  -> container: /home/bun/.openclaw/openclaw.json (read-only bind)
```

1Password の値変更後は再展開してコンテナ再起動する。

```powershell
chezmoi apply
docker restart openclaw
```

## セキュリティ制約（設計前提）

`docker-compose.yml` は以下前提で維持する。

- `read_only: true`
- `tmpfs: /tmp`
- `cap_drop: [ALL]`
- `security_opt: no-new-privileges:true`
- `user: "1000:1000"`

つまり、コンテナ内で永続的に書き込めるのは volume と tmpfs のみ。

## 必須ボリューム（書き込み先）

- `openclaw-home` -> `/home/bun/.openclaw`（openclaw state）
- `openclaw-acpx` -> `/home/bun/.acpx`（acpx runtime state）
- `openclaw-data` -> `/app/data`（workspace / skills / .bun）
- bind mount -> `/home/bun/.openclaw/openclaw.json`（config read-only）
- bind mount -> `/home/bun/.claude`（Claude Code OAuth 認証情報）
- bind mount -> `/home/bun/.claude.json:ro`（Claude Code 設定ファイル）
- bind mount -> `/home/bun/.gemini`（Gemini CLI OAuth 認証情報）

## GitHub 認証の実装ルール

- 認証方式は Fine-grained PAT のみ（Classic PAT 不使用）
- PAT は 1Password から起動時に取得し、Docker secret `github_token` として注入
- コンテナ内 git 認証は `GIT_ASKPASS=/usr/local/bin/git-credential-askpass.sh` を使う
- `entrypoint.sh` が `/run/secrets/github_token` を読み、`GITHUB_TOKEN` と `GH_TOKEN` をプロセス環境へ export
- `Dockerfile` 側で `git-credential-askpass.sh` を配置する

1Password 参照先:

```text
op://Personal/GitHubUsedOpenClawPAT/credential
```

`.env` が既にある場合、Handler の `EnsureEnvFile` は再生成をスキップする。再生成したい場合:

```powershell
Remove-Item docker\openclaw\.env
pwsh -File scripts\powershell\install.user.ps1
```

手動起動する場合は `OPENCLAW_GITHUB_TOKEN_FILE` をセットする。
（Handler は `~/.openclaw/secrets/github_token` を自動設定する）

## 手動操作コマンド（Handler 非経由時）

```powershell
docker compose -f docker/openclaw/docker-compose.yml up -d --build
docker compose -f docker/openclaw/docker-compose.yml down
docker compose -f docker/openclaw/docker-compose.yml logs -f
docker exec -it openclaw sh
```

## Claude Code ACP 連携（ACPX 経由）

### 構成

OpenClaw から Claude Code を ACP エージェントとして呼び出す。
Claude Code 自身の OAuth（Claude Max）で認証するため、Anthropic の利用規約に抵触しない。

```text
OpenClaw (Codex) -> sessions_spawn(runtime:"acp", agentId:"claude")
  -> acpx -> claude-agent-acp (ACP アダプタ)
    -> claude --dangerously-skip-permissions (Claude Code CLI)
      -> Anthropic API (OAuth 認証)
```

### インストール要件

Dockerfile に以下 2 パッケージが必要:

- `@anthropic-ai/claude-code` — Claude Code CLI 本体
- `@zed-industries/claude-agent-acp` — ACP プロトコルアダプタ

`claude-agent-acp` は **必ず Dockerfile でグローバルインストール** する。
`read_only: true` + `cap_drop: ALL` 環境では `npx` による動的ダウンロードが以下の理由で失敗する:

1. npm キャッシュディレクトリ (`/home/bun/.npm`) が read-only FS 上で作成不可
2. tmpfs を追加しても `ENOSPC`（パッケージサイズ > tmpfs サイズ）
3. tmpfs サイズを十分確保しても `Permission denied`（実行ビット問題）

### acpx.config.json の設定

```json
{
  "agents": {
    "claude": {
      "command": "claude-agent-acp"
    }
  }
}
```

**注意**: `"command": "claude --dangerously-skip-permissions"` のようにClaude Code を直接指定してはならない。
ACPX は ACP プロトコル（JSON-RPC）で通信するが、Claude Code CLI は ACP を直接サポートしないため、
`initialize` フェーズでタイムアウトする。`claude-agent-acp` がプロトコル変換を行う。

### ホスト側の認証情報マウント

Claude Code は OAuth 認証情報を 2 箇所に保持する:

| ホスト           | コンテナ                 | 内容                                                   |
| ---------------- | ------------------------ | ------------------------------------------------------ |
| `~/.claude/`     | `/home/bun/.claude`      | `.credentials.json`（OAuth トークン）, `settings.json` |
| `~/.claude.json` | `/home/bun/.claude.json` | プロファイル設定（HOME ルートに配置が必要）            |

`.claude.json` は `$HOME/.claude.json`（HOME ルート直下）に存在しなければならない。
`$HOME/.claude/.claude.json` ではないので注意。`docker-compose.yml` で `:ro` バインドマウントする。

### entrypoint.sh での初期化

コンテナ起動時に `/home/bun/.claude/settings.json` が存在しなければ、
ヘッドレス動作用のデフォルト設定を書き込む（`hasCompletedOnboarding: true` + 全ツール許可）。

### 動作確認コマンド

```bash
# Claude Code 単体テスト（OAuth 認証確認）
docker exec openclaw claude --dangerously-skip-permissions -p "Reply exactly: pong" --output-format json

# ACPX 経由テスト（ACP プロトコル確認）
MSYS_NO_PATHCONV=1 docker exec openclaw acpx --verbose --timeout 180 claude exec "Reply exactly: pong"
```

期待出力（ACPX）:

```
[acpx] spawning agent: claude-agent-acp
[client] initialize (running)
[acpx] initialized protocol version 1
[client] session/new (running)
pong
[done] end_turn
```

### OpenClaw バージョン要件

OpenClaw 2026.3.2 以降を推奨。2026.3.1 以前では ACPX が Claude Code を PTY なしで
spawn し、Ink (React terminal UI) の raw mode 要件でクラッシュする（PR #34020 で修正）。

## 既知障害の一次切り分け

- `acpx exited with code 1`
  - `openclaw-acpx` が `/home/bun/.acpx` に mount され、書き込み可能か確認
- `Invalid JSON in /home/bun/.acpx/config.json`
  - `config.json` の途中切れ（0 byte / 壊れ JSON）を疑う
  - `entrypoint.sh` が `/app/acpx.config.json` を起動時に再投入する設計なので、`docker compose up -d --build --force-recreate` を優先
  - コンテナ内確認: `cat /home/bun/.acpx/config.json`
- `acpx: not found`
  - `openclaw.docker.json` の `plugins.entries.acpx.config.command` を `/usr/local/bin/acpx` に固定
- `sessions_spawn(runtime:"acp", agentId:"claude")` が initialize で詰まる
  - `acpx.config.json` の `agents.claude.command` が `claude-agent-acp` であることを確認（`claude --dangerously-skip-permissions` は不可。ACP 非対応）
  - `claude-agent-acp` が `/usr/local/bin/` にインストール済みか確認: `docker exec openclaw which claude-agent-acp`
  - OpenClaw 2026.3.2 以降であることを確認（PTY 修正 PR #34020）
- `sessions_spawn(runtime:"acp", agentId:"claude")` で `ENOENT` / `Permission denied`
  - `@zed-industries/claude-agent-acp` を npx ではなく Dockerfile でグローバルインストールしているか確認
  - read-only FS 環境では npx 動的インストールは動作しない（上記「Claude Code ACP 連携」セクション参照）
- Claude Code が `Claude configuration file not found at: /home/bun/.claude.json` を出す
  - `docker-compose.yml` で `${CLAUDE_CONFIG_JSON}:/home/bun/.claude.json:ro` がマウントされているか確認
  - `.env` に `CLAUDE_CONFIG_JSON` が設定されているか確認
  - ホスト側の `~/.claude.json`（HOME ルート直下）が存在するか確認
- `sessions_spawn(runtime:"acp")` が initialize で詰まる（Gemini）
  - `acpx.config.json` の `agents.gemini.command` を `gemini --experimental-acp -m gemini-2.5-flash-lite` に固定（デフォルト `gemini` のままだと ACP ハンドシェイク未成立）
  - `docker-compose.yml` の `environment.HOME` を `/home/bun` に固定し、認証ファイル参照先を安定化する
- `sessions_spawn(runtime:"acp")` が 429 で失敗
  - ローカル設定不備ではなく Gemini 側の一時容量制限 (`MODEL_CAPACITY_EXHAUSTED`) を疑う
- `sessions_send` が `ok` でも本文を返さない
  - 既知挙動として payload 本文が空/保留になるケースがある
  - `docker logs openclaw` の `[agent:nested] session=agent:gemini:acp:...` 行で実本文を確認する
- `plugin telegram: duplicate plugin id`
  - `/home/bun/.openclaw/extensions/telegram` の旧拡張を退避/削除し、stock 側のみ利用
- Slack 接続が確立しない / `slack: not connected`
  - 1Password の `SlackBot-OpenClaw` に `botToken`（`xoxb-...`）と `appToken`（`xapp-...`）が正しく登録されているか確認
  - Slack App で Socket Mode が有効化されているか確認（Settings → Socket Mode → Enable）
  - `appToken` のスコープに `connections:write` が含まれているか確認
  - `docker logs openclaw | grep -i slack` で接続エラーの詳細を確認
- Slack で DM が無視される
  - `allowFrom` に自分の Slack User ID（`U` で始まる文字列）が設定されているか確認
  - 1Password `op://Personal/Slack/MIKI_CO/slack_user_id` の値を確認
  - Slack App の Bot Token Scopes に `im:history`, `im:read`, `im:write` が含まれているか確認
  - Slack App の App Home → Messages Tab が有効化されているか確認

## サブエージェント完了判定の運用ルール

- デフォルトは Codex 子（`sessions_spawn` で `runtime:"acp"` を付けず `agentId:"main"`）を使う
- Claude 子は `sessions_spawn(runtime:"acp", agentId:"claude")` で明示指定する
- Gemini 子は `sessions_spawn(runtime:"acp", agentId:"gemini")` で明示指定する
- announce は `best-effort` のため、完了判定の唯一ソースにしない
- `sessions_spawn` 後は `runId` / `childSessionKey` を保持する
- 子への実タスク送信は `sessions_send(timeoutSeconds>0)` で同期回収する（推奨）
- `sessions_history` は補助用途に限定する（環境によって空を返すケースがある）
- `accepted` は投入成功のみ。`completed/failed/timed out` を必ず別途判定する
- `429 MODEL_CAPACITY_EXHAUSTED` は再試行（指数バックオフ）を前提にする
- 追跡不能が起きる場合は `chezmoi/dot_openclaw/openclaw.docker.json.tmpl` で以下を確認する
  - `agents.defaults.subagents.maxSpawnDepth = 2`
  - `agents.defaults.sandbox.sessionToolsVisibility = "all"`
  - `tools.sessions.visibility = "all"`
  - `tools.agentToAgent.enabled = true`

参照:

- https://docs.openclaw.ai/tools/subagents
- https://docs.openclaw.ai/concepts/session-tool
- https://docs.openclaw.ai/tools/acp-agents
- https://docs.openclaw.ai/tools
- https://github.com/openclaw/openclaw/issues/28786 (PTY fix for Claude Code ACP)
- https://github.com/openclaw/openclaw/issues/29593
- https://github.com/openclaw/openclaw/pull/32683
- https://github.com/openclaw/acpx
