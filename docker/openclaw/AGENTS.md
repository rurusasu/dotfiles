# openclaw Docker: 実装時の必須ルール

このディレクトリは、openclaw (Telegram / Slack AI gateway) を Docker で動かすための構成を管理する。

## 変更時に必ず触るファイル

- `docker/openclaw/Dockerfile`
- `docker/openclaw/docker-compose.yml`
- `docker/openclaw/entrypoint.sh`
- `docker/openclaw/config/acpx.config.json`
- `docker/openclaw/config/gemini.settings.json`
- `docker/openclaw/.env`（通常は自動生成。手動編集は最小限）
- `chezmoi/dot_openclaw/openclaw.docker.json.tmpl`（設定の source of truth）
- `docker/openclaw/apps/sandbox/` — sandbox サイドカーコンテナ

## 起動と再生成の正規フロー

`scripts/powershell/install.user.ps1` (Handler.OpenClaw.ps1) が以下を一括実行する。

1. `chezmoi apply` で設定を展開
2. `.env` を生成（`OPENCLAW_CONFIG_FILE` など。シークレットは含めない）
3. 1Password からシークレットを取得し、環境変数にセット（`OPENCLAW_GITHUB_TOKEN`, `OPENCLAW_XAI_API_KEY`）
4. `docker compose up -d --build` で起動（Docker Compose が環境変数から environment-based secret を生成し、コンテナ内 `/run/secrets/` に注入）

通常の起動・復旧はこのコマンドを使う。

```powershell
pwsh -File scripts/powershell/install.user.ps1
```

## 設定値の流れ（変更影響の把握用）

```text
1Password secret
  -> chezmoi template (dot_openclaw/openclaw.docker.json.tmpl)
  -> ~/.openclaw/openclaw.docker.json
  -> container: /home/app/.openclaw/openclaw.json (read-only bind)
```

1Password の値変更後は再展開してコンテナ再起動する。

```powershell
chezmoi apply
docker restart openclaw
```

## セキュリティ制約（設計前提）

### コンテナ硬化

`docker-compose.yml` は以下前提で維持する。

- `read_only: true`
- `tmpfs: /tmp`
- `cap_drop: [ALL]`
- `security_opt: no-new-privileges:true`
- `user: "1000:1000"`
- `pids_limit: 256`
- `mem_limit: 2g`
- ポートは `127.0.0.1` にバインド（外部公開しない）

つまり、コンテナ内で永続的に書き込めるのは volume と tmpfs のみ。

ビルトイン sandbox コンテナは OpenClaw が Docker Engine 経由で自動生成するため、
上記の hardened ルールは Gateway コンテナ自体に適用される。
sandbox コンテナの隔離は `agents.defaults.sandbox.docker` 設定（`network: "bridge"` 等）で制御する。

### チャンネルアクセス制御

- Telegram: `dmPolicy: "allowlist"` + `allowFrom` でユーザー ID を限定
- Slack DM: `dmPolicy: "allowlist"` + `allowFrom` でユーザー ID を限定
- Slack チャンネル: `groupPolicy: "allowlist"` + `channels` で許可チャンネル ID を明示指定、`requireMention: true`
- Slack ユーザー ID は 1Password に保存（アカウント特定に使えるため）
- Slack チャンネル ID はテンプレートにべた書きで可（URL に含まれる公開情報であり秘匿不要）

### Gateway

- `gateway.mode: "local"` + `gateway.bind: "loopback"` + `gateway.auth.mode: "token"` で保護
- gateway token は 1Password から取得

## 必須ボリューム（書き込み先）

### openclaw コンテナ

- `openclaw-home` -> `/home/app/.openclaw`（openclaw state）
- `openclaw-acpx` -> `/home/app/.acpx`（acpx runtime state）
- `openclaw-data` -> `/app/data`（workspace / skills）
- bind mount -> `/home/app/.openclaw/openclaw.json`（config read-only）
- bind mount -> `/home/app/.claude`（Claude Code OAuth 認証情報）
- bind mount -> `/home/app/.claude.json:ro`（Claude Code 設定ファイル）
- bind mount -> `/home/app/.gemini`（Gemini CLI OAuth 認証情報）

### Docker socket

- `/var/run/docker.sock` -> `/var/run/docker.sock`（ビルトイン sandbox のコンテナ生成に必要）

## シークレット注入の実装ルール

すべての 1Password 由来シークレットは **Docker Compose file-based secrets** で注入する。
シークレットファイルは `~/.openclaw/secrets/` に永続化し、`.env` からパスを参照する。

### なぜ `file:` ベースか（`environment:` ベースを使わない理由）

Docker Compose の `environment:` ベース secrets は、コンテナ作成後・起動前に `docker cp` でコンテナ内に書き込む実装。
`read_only: true` 環境ではルートファイルシステムへの書き込みが拒否されるため **構造的に動作しない**。
`file:` ベースは bind mount で処理されるため `read_only: true` でも動作する。
これは Docker Engine API の制限であり、修正の見込みなし。

参照:

- https://github.com/docker/compose/issues/12031 (configs + read_only の根本原因説明)
- https://github.com/docker/compose/issues/12303 (secrets + read_only の feature request、12031 の duplicate としてクローズ)

### 設計方針

- **禁止**: `docker-compose.yml` の `environment` セクションにシークレットを直接書かないこと（`docker inspect` で丸見えになる）
- **禁止**: シークレットファイルを `finally` ブロックで削除しないこと（コンテナ再作成時に secret が空になる）
- **禁止**: `secrets.*.environment` を使わないこと（`read_only: true` と非互換）
- Handler が 1Password からシークレットを取得 → `~/.openclaw/secrets/` にファイルとして永続化 → `.env` にファイルパスを記録 → `docker compose up` が `file:` 経由で `/run/secrets/` に注入
- `entrypoint.sh` が `/run/secrets/*` を読み取り、アプリケーション用の環境変数（`GITHUB_TOKEN`, `XAI_API_KEY` 等）にセットする
- コンテナ内 git 認証は `GIT_ASKPASS=/usr/local/bin/git-credential-askpass.sh` が `GITHUB_TOKEN` 環境変数を返す

### シークレット一覧

| 1Password 参照先                                 | ホスト側ファイル                   | `.env` 変数名                | コンテナ内                                   | 必須 |
| ------------------------------------------------ | ---------------------------------- | ---------------------------- | -------------------------------------------- | ---- |
| `op://Personal/GitHubUsedOpenClawPAT/credential` | `~/.openclaw/secrets/github_token` | `OPENCLAW_GITHUB_TOKEN_FILE` | `/run/secrets/github_token` → `GITHUB_TOKEN` | Yes  |
| `op://Personal/xAI-Grok-Twitter/console/apikey`  | `~/.openclaw/secrets/xai_api_key`  | `OPENCLAW_XAI_API_KEY_FILE`  | `/run/secrets/xai_api_key` → `XAI_API_KEY`   | No   |

### GitHub PAT の要件

- Fine-grained PAT のみ（Classic PAT 不使用）
- 対象リポジトリへの `Contents: Read and write` 権限が必要（push するため）

`.env` が既にある場合、Handler の `EnsureEnvFile` は再生成をスキップする。再生成したい場合:

```powershell
Remove-Item docker\openclaw\.env
pwsh -File scripts\powershell\install.user.ps1
```

手動起動（file-based secret でトークン注入）:

```powershell
$secretDir = "$env:USERPROFILE\.openclaw\secrets"
New-Item -ItemType Directory -Path $secretDir -Force | Out-Null
op read "op://Personal/GitHubUsedOpenClawPAT/credential" | Set-Content -NoNewline "$secretDir\github_token"
op read "op://Personal/xAI-Grok-Twitter/console/apikey" | Set-Content -NoNewline "$secretDir\xai_api_key"
$env:OPENCLAW_GITHUB_TOKEN_FILE = ($secretDir -replace '\\', '/') + '/github_token'
$env:OPENCLAW_XAI_API_KEY_FILE = ($secretDir -replace '\\', '/') + '/xai_api_key'
docker compose -f docker/openclaw/docker-compose.yml up -d --build
```

## 手動操作コマンド（Handler 非経由時）

```powershell
docker compose -f docker/openclaw/docker-compose.yml up -d --build
docker compose -f docker/openclaw/docker-compose.yml down
docker compose -f docker/openclaw/docker-compose.yml logs -f
docker exec -it openclaw sh
```

## Claude Code ACP 連携（ACPX 経由）

### 禁止事項: OpenClaw のメインモデルに Claude Max 認証を使用しないこと

OpenClaw の `agents.defaults.model` を `anthropic/claude-opus-4-6` 等に変更し、
Claude Max の setup-token（`claude setup-token`）や OAuth トークンで認証してはならない。

Anthropic の Consumer ToS（2026年2月改定）により、Claude Free/Pro/Max の OAuth 認証は
**Claude Code と claude.ai 専用** と明確化されている。OpenClaw のメインモデルとして
Claude Max 認証を使うのは規約違反となる。

> OAuth authentication (used with Free, Pro, and Max plans) is intended exclusively
> for Claude Code and Claude.ai. Using OAuth tokens obtained through Claude Free, Pro,
> or Max accounts in any other product, tool, or service is not permitted.

Anthropic API Key（従量課金）または Bedrock/Vertex 経由であれば問題ない。

参照: https://www.theregister.com/2026/02/20/anthropic_clarifies_ban_third_party_claude_access/

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

1. npm キャッシュディレクトリ (`/home/app/.npm`) が read-only FS 上で作成不可
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
| `~/.claude/`     | `/home/app/.claude`      | `.credentials.json`（OAuth トークン）, `settings.json` |
| `~/.claude.json` | `/home/app/.claude.json` | プロファイル設定（HOME ルートに配置が必要）            |

`.claude.json` は `$HOME/.claude.json`（HOME ルート直下）に存在しなければならない。
`$HOME/.claude/.claude.json` ではないので注意。`docker-compose.yml` で `:ro` バインドマウントする。

### entrypoint.sh での初期化

コンテナ起動時に `/home/app/.claude/settings.json` が存在しなければ、
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

## スキルとサブエージェント

- ニュース収集・X/Twitter 投稿取得などの手順は `skills/news/SKILL.md` に集約されている
- OpenClaw（Codex）は調査・Web 取得タスクを Claude Code サブエージェントに委譲する: `sessions_spawn(runtime:"acp", agentId:"claude")`
- スキルは `entrypoint.sh` が `/home/app/.claude/skills/` → `/app/data/workspace/skills/` にシンボリックリンクで配置する

### cognee-skills MCP（スキル自己改善システム）

cognee-skills は「スキルを時間とともに自己改善させる」ための MCP サーバーである。
スキルの実行結果を記録・分析し、失敗パターンに基づく改善提案→適用→評価→ロールバックのループを自動化する。

参照: https://github.com/topoteretes/cognee / https://pypi.org/project/cognee/

#### 接続情報

- プラグイン: `openclaw-mcp-bridge`（`plugins.entries` で設定）
- トランスポート: `streamable-http`
- エンドポイント: `http://cognee-mcp-skills:8000/mcp`（同一 Docker ネットワーク内、認証不要）
- ツールプレフィックス: `cognee_skills_`（`toolPrefix: true`）
- ツールは Gateway 側で実行される（sandbox 経由ではない）

#### 対象スキル一覧

以下のスキルが cognee-skills の追跡・改善対象となる。`skill_name` パラメータには左列の名前を使用する。

| `skill_name`                | パス                                | 概要                                   |
| --------------------------- | ----------------------------------- | -------------------------------------- |
| `news`                      | `skills/news/`                      | テックニュース収集（Zenn/はてブ/HN/X） |
| `codex`                     | `skills/codex/`                     | Codex CLI 連携                         |
| `create-agentsmd`           | `skills/create-agentsmd/`           | AGENTS.md/CLAUDE.md 生成               |
| `create-mixin`              | `skills/create-mixin/`              | Mixin パターン抽出                     |
| `dockerfile-optimization`   | `skills/dockerfile-optimization/`   | Dockerfile 最適化                      |
| `python-clean-architecture` | `skills/python-clean-architecture/` | Python クリーンアーキテクチャ          |
| `python-docstring`          | `skills/python-docstring/`          | Python docstring 生成                  |
| `skill-creator`             | `skills/skill-creator/`             | スキル作成支援                         |
| `taskfile-creation`         | `skills/taskfile-creation/`         | Taskfile.yml 作成                      |
| `video-intake`              | `skills/video-intake/`              | 動画取り込みワークフロー               |

#### ツールと自己改善サイクル

```
観察(Observe) → 検査(Inspect) → 修正(Amend) → 評価(Evaluate) → ロールバック or 採用
```

| #   | フェーズ     | ツール名                               | 説明                               | いつ使うか                                          |
| --- | ------------ | -------------------------------------- | ---------------------------------- | --------------------------------------------------- |
| 1   | 観察         | `cognee_skills_log_skill_execution`    | スキル実行結果を記録               | **毎回のスキル実行後に必ず呼ぶ**                    |
| 2   | 観察         | `cognee_skills_search_skill_history`   | 過去の実行履歴を検索               | 失敗傾向の調査時                                    |
| 3   | 検査         | `cognee_skills_get_skill_status`       | 成功率・失敗パターンのサマリー     | 定期的な健全性チェック                              |
| 4   | 検査         | `cognee_skills_get_skill_improvements` | 失敗パターンに基づく改善提案を生成 | `min_executions` 回以上の履歴が必要（デフォルト 5） |
| 5   | 修正         | `cognee_skills_amend_skill`            | 改善提案を SKILL.md に適用         | 提案を承認した後                                    |
| 6   | 評価         | `cognee_skills_evaluate_amendment`     | 改善後のスコアを比較               | 改善適用後に十分な実行データが溜まった後            |
| 7   | ロールバック | `cognee_skills_rollback_skill`         | 改善前の状態に戻す                 | 評価で効果なしと判断された場合                      |

#### 運用ルール

- **スキル実行後は必ず `cognee_skills_log_skill_execution` を呼ぶ**。これがないと改善ループが回らない
- パラメータ例:

```
cognee_skills_log_skill_execution(
  skill_name="news",
  agent="claude",
  task_description="テックニュース収集",
  success=true,
  duration_ms=15000
)
```

- 失敗時は `error` パラメータにエラー内容を含める:

```
cognee_skills_log_skill_execution(
  skill_name="news",
  agent="claude",
  task_description="テックニュース収集",
  success=false,
  error="web_fetch timeout for zenn.dev",
  duration_ms=30000
)
```

- `cognee_skills_get_skill_improvements` は最低 `min_executions` 回（デフォルト 5）の実行履歴がないと提案を生成しない
- `cognee_skills_amend_skill` は SKILL.md を直接書き換える。変更は `chezmoi re-add` でホスト側に同期すること（「スキル変更のコミット手順」参照）
- cognee-skills コンテナが停止中はツール呼び出しがタイムアウトする。`docker compose -f docker/cognee-skills/docker-compose.yml up -d` で起動
- X/Twitter URL は `web_fetch` 不可（JS 必須）。Grok API `x_search` + `$XAI_API_KEY` を使用（詳細は `skills/news/SKILL.md`）

### Superpowers（obra/superpowers）

[obra/superpowers](https://github.com/obra/superpowers) スキルフレームワークがコンテナ内の全エージェントに自動配信される。

**仕組み:**

- `entrypoint.sh` が `/app/data/superpowers` に `obra/superpowers` を shallow clone
- 各エージェントのスキル検出パスにシンボリックリンクで配線:

| エージェント     | 検出パス                                             | リンク対象     |
| ---------------- | ---------------------------------------------------- | -------------- |
| Codex / OpenCode | `~/.agents/skills/superpowers`                       | `skills/`      |
| Gemini CLI       | `~/.gemini/extensions/superpowers`                   | リポジトリ全体 |
| Claude Code      | ホスト側 marketplace plugin がマウント経由で利用可能 |
| Workspace 経由   | `/app/data/workspace/skills/superpowers`             | `skills/`      |

**更新:**

- コンテナ再起動時に `git pull --ff-only` で自動更新
- pull 失敗時はキャッシュ版で続行（コンテナ起動を妨げない）

**新しい ACP エージェントに superpowers を追加する手順:**

1. そのエージェントのスキル検出パスを確認（公式ドキュメントまたは obra/superpowers の README 参照）
2. `entrypoint.sh` の `# --- Superpowers: wire to agent skill-discovery paths ---` セクションに追加:

```sh
# <AgentName>
mkdir -p "$HOME/<agent-config-dir>"
ln -sfn "$_sp_dir/skills" "$HOME/<agent-config-dir>/superpowers"
```

3. 検出パスが read-only FS 上の場合、`docker-compose.yml` の tmpfs に追加:

```yaml
tmpfs:
  - /home/app/<agent-config-dir>:size=1m,mode=0755
```

4. Gemini CLI のようにリポジトリ全体を期待するエージェントは `$_sp_dir` をリンク（`$_sp_dir/skills` ではなく）
5. `tests/test-entrypoint.sh` の `run_superpowers_wiring` にリンク先を追加しテストを更新

### スキル変更のコミット手順

コンテナ内でスキルを編集した場合、変更は symlink 経由でホストの `~/.claude/skills/` に自動反映される。
ただし Git の管理対象は `chezmoi/dot_claude/skills/` であるため、**ホスト側で chezmoi re-add を実行**してソースに同期する必要がある。

```text
コンテナ内編集
  /app/data/workspace/skills/  (symlink)
    → /home/app/.claude/skills/  (bind mount)
      → ホスト ~/.claude/skills/  (自動反映)
        → chezmoi re-add でソースに同期
          → chezmoi/dot_claude/skills/  (Git 管理下)
```

**手順（ホスト側で実行）:**

```powershell
# 1. 差分確認
chezmoi diff ~/.claude/skills/

# 2. 変更をソースに同期（特定ファイル）
chezmoi re-add ~/.claude/skills/<skill-name>/SKILL.md

# 3. 一括同期（全スキル）
chezmoi re-add ~/.claude/skills/

# 4. git diff で確認後コミット
git -C D:\dotfiles diff chezmoi/dot_claude/skills/
git -C D:\dotfiles add chezmoi/dot_claude/skills/
git -C D:\dotfiles commit
```

**注意**: `chezmoi re-add` はホスト側でのみ実行可能（コンテナ内に chezmoi は未インストール）。

xAI API Key の 1Password 参照先:

```text
op://Personal/xAI-Grok-Twitter/console/apikey
```

## 既知障害の一次切り分け

- `acpx exited with code 1`
  - `openclaw-acpx` が `/home/app/.acpx` に mount され、書き込み可能か確認
- `Invalid JSON in /home/app/.acpx/config.json`
  - `config.json` の途中切れ（0 byte / 壊れ JSON）を疑う
  - `entrypoint.sh` が `/app/acpx.config.json` を起動時に再投入する設計なので、`docker compose up -d --build --force-recreate` を優先
  - コンテナ内確認: `cat /home/app/.acpx/config.json`
- `acpx: not found`
  - `openclaw.docker.json` の `plugins.entries.acpx.config.command` を `/usr/local/bin/acpx` に固定
- `sessions_spawn(runtime:"acp", agentId:"claude")` が initialize で詰まる
  - `acpx.config.json` の `agents.claude.command` が `claude-agent-acp` であることを確認（`claude --dangerously-skip-permissions` は不可。ACP 非対応）
  - `claude-agent-acp` が `/usr/local/bin/` にインストール済みか確認: `docker exec openclaw which claude-agent-acp`
  - OpenClaw 2026.3.2 以降であることを確認（PTY 修正 PR #34020）
- `sessions_spawn(runtime:"acp", agentId:"claude")` で `ENOENT` / `Permission denied`
  - `@zed-industries/claude-agent-acp` を npx ではなく Dockerfile でグローバルインストールしているか確認
  - read-only FS 環境では npx 動的インストールは動作しない（上記「Claude Code ACP 連携」セクション参照）
- Claude Code が `Claude configuration file not found at: /home/app/.claude.json` を出す
  - `docker-compose.yml` で `${CLAUDE_CONFIG_JSON}:/home/app/.claude.json:ro` がマウントされているか確認
  - `.env` に `CLAUDE_CONFIG_JSON` が設定されているか確認
  - ホスト側の `~/.claude.json`（HOME ルート直下）が存在するか確認
- `sessions_spawn(runtime:"acp")` が initialize で詰まる（Gemini）
  - `acpx.config.json` の `agents.gemini.command` を `gemini --experimental-acp -m gemini-2.5-flash-lite` に固定（デフォルト `gemini` のままだと ACP ハンドシェイク未成立）
  - `docker-compose.yml` の `environment.HOME` を `/home/app` に固定し、認証ファイル参照先を安定化する
- `sessions_spawn(runtime:"acp")` が 429 で失敗
  - ローカル設定不備ではなく Gemini 側の一時容量制限 (`MODEL_CAPACITY_EXHAUSTED`) を疑う
- `sessions_send` が `ok` でも本文を返さない
  - 既知挙動として payload 本文が空/保留になるケースがある
  - `docker logs openclaw` の `[agent:nested] session=agent:gemini:acp:...` 行で実本文を確認する
- `plugin telegram: duplicate plugin id`
  - `/home/app/.openclaw/extensions/telegram` の旧拡張を退避/削除し、stock 側のみ利用
- DNS 障害で Slack / Telegram が応答不能になる
  - ログに `getaddrinfo ENOTFOUND slack.com` や `pong wasn't received` が連続する場合、ネットワーク一時障害による接続断
  - Slack Socket Mode には openclaw 側に再接続設定がなく、Bolt ライブラリ内部任せ。DNS 障害後にリカバリーできずハングすることがある
  - Telegram は `channels.telegram.retry` でリトライ回数を増やし、`channels.telegram.network` で IPv6 問題を回避できる
  - 最終防衛は Docker healthcheck（`/health` エンドポイント）+ `restart: unless-stopped` による自動再起動
  - `docker-compose.yml` の healthcheck 設定: `interval: 30s`, `timeout: 10s`, `retries: 3`, `start_period: 60s`
  - healthcheck は Gateway プロセスの HTTP 応答のみを検査する。Slack/Telegram の接続状態までは検知しないため、プロセスがハングせず HTTP だけ応答する場合は再起動されない
- Slack 接続が確立しない / `slack: not connected`
  - 1Password の `SlackBot-OpenClaw` に `botToken`（`xoxb-...`）と `appToken`（`xapp-...`）が正しく登録されているか確認
  - Slack App で Socket Mode が有効化されているか確認（Settings → Socket Mode → Enable）
  - `appToken` のスコープに `connections:write` が含まれているか確認
  - `docker logs openclaw | grep -i slack` で接続エラーの詳細を確認
- Slack で DM が無視される
  - `allowFrom` に自分の Slack User ID（`U` で始まる文字列）が設定されているか確認
  - 1Password `op://Personal/22w7ub2pldlpo6tlmggc7g67mu/Miki _Co/slack_user_id` の値を確認
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

## ビルトイン Sandbox

### 概要

OpenClaw のビルトイン sandbox 機能を使い、エージェントのツール実行（`shell_exec`, `file_write` 等）を
隔離された sibling Docker コンテナ内で自動実行する。

### 仕組み

- Gateway が Docker Engine API 経由で sandbox コンテナを自動生成
- Docker socket（`/var/run/docker.sock`）を Gateway コンテナにマウントして実現
- セッションごとに独立コンテナ（`scope: "session"`）、セッション終了時に自動削除
- イメージ `openclaw-sandbox-common:bookworm-slim` に Python 3, Node.js, git, curl, jq が含まれる

### パスマッピング（重要）

sandbox コンテナではワークスペースが `/workspace` にマウントされるが、
**sandbox の `/workspace` と Gateway の `/app/data/workspace/` は同一ディレクトリではない**。

Docker volume（`openclaw-data`）は Gateway コンテナにマウントされているが、
sandbox は sibling コンテナとして Docker Engine から直接作成される。
OpenClaw が sandbox に渡す bind source `/app/data/workspace` は Gateway 内のパスであり、
Docker Engine はこれをホスト上のパスとして解釈するため、Gateway の volume とは異なる場所を指す。

結果として、**sandbox 内の `file_write` で `/workspace/` に書いたファイルは Gateway 側には反映されない**。

### sandbox 書き込みの制約と運用ルール

| 操作             | 方法                                          | 備考                               |
| ---------------- | --------------------------------------------- | ---------------------------------- |
| 永続メモリの保存 | Gateway の `memory_save` ツール（qmd/SQLite） | sandbox の `file_write` は使わない |
| 永続メモリの検索 | Gateway の `memory_search` ツール             | 同上                               |
| ファイルの永続化 | sandbox 内で `git commit` → `git push`        | 外部リポジトリ経由で永続化         |
| AGENTS.md の編集 | Gateway 側の cron または直接操作              | sandbox からは不可                 |

**禁止事項:**

- sandbox の `/workspace/memory/` に `file_write` でメモリを保存してはならない（Gateway に反映されない）
- 「覚える」操作は必ず `memory_save` / `memory_search` を使うこと

### 設定（`openclaw.docker.json.tmpl`）

```json
"sandbox": {
  "sessionToolsVisibility": "all",
  "mode": "all",
  "scope": "session",
  "workspaceAccess": "none",
  "docker": {
    "image": "openclaw-sandbox-common:bookworm-slim",
    "network": "bridge"
  }
}
```

`workspaceAccess` は `"none"` に設定する。`"rw"` にしても上記のパスマッピング問題により
Gateway 側との共有は実現しない。カスタム `binds` で volume パスを直接指定する方法も、
OpenClaw の sandbox セキュリティ（予約パスの保護、許可ルート外のソース拒否）により使用不可。

### Docker socket マウントのセキュリティ

Docker socket アクセスは Gateway に任意のコンテナ操作権限を与える。以下で緩和:

- `dmPolicy: "allowlist"` でユーザーを限定（信頼できるユーザーのみ Gateway を操作可能）
- sandbox コンテナは `network: "bridge"`（外部通信可能 — Playwright E2E、API 呼び出し等に必要）
- sandbox コンテナに注入するシークレットは許可リストで管理する（下記「Sandbox シークレットポリシー」参照）
- Gateway 自体は `read_only: true` + `cap_drop: ALL`

### sandbox イメージのビルド

sandbox イメージは **ホスト側で BuildKit を使ってビルドする**（コンテナ内の legacy builder
では ARG 評価の問題があるため）。`entrypoint.sh` は起動時にイメージの存在を確認し、
不足していれば警告を出す。

- `openclaw-sandbox:bookworm-slim` — ベースイメージ（Debian slim + 基本ツール）
- `openclaw-sandbox-common:bookworm-slim` — 実行イメージ（+ pnpm, Python 3, Node.js, npm, git 等）

```bash
# 初回 or イメージ再ビルド時
task sandbox:build

# イメージ削除 → 再ビルド
docker rmi openclaw-sandbox-common:bookworm-slim openclaw-sandbox:bookworm-slim
task sandbox:build
```

### 動作確認コマンド

```bash
# sandbox 設定の確認
docker exec openclaw openclaw sandbox explain

# sandbox イメージの確認
docker exec openclaw docker images | grep sandbox

# 実行中の sandbox コンテナ一覧
docker ps --filter "ancestor=openclaw-sandbox-common:bookworm-slim"
```

### Playwright CLI（ブラウザ自動操作）

sandbox イメージには `@playwright/cli` と Chromium がプリインストールされている。

- `SYS_ADMIN` 不要 — Playwright はデフォルトで `--no-sandbox` で Chromium を起動する（`chromiumSandbox: false`）
- `capDrop: ["ALL"]` のままで動作する
- `network: "bridge"` — 外部 URL へのアクセスに必要（`"none"` では不可）
- `PLAYWRIGHT_BROWSERS_PATH` 環境変数 — ビルド時にインストールしたブラウザのパスを明示
- `@playwright/test` は使用しない。`@playwright/cli` のみ使用する

### 既知障害の一次切り分け

- sandbox コンテナが起動しない
  - `docker exec openclaw docker info` で socket アクセスを確認
  - WSL2: Docker Desktop 設定で socket 経由を使用しているか確認
- sandbox イメージが見つからない
  - `docker exec openclaw openclaw sandbox build` でイメージをビルド
  - `OPENCLAW_SANDBOX=1` が `docker-compose.yml` の `environment` に設定されているか確認
- sandbox 内でパッケージインストールが失敗
  - sandbox イメージにプリインストールされていないパッケージは `docker.setupCommand` で事前インストールするか、カスタムイメージを使う

参照:

- https://docs.openclaw.ai/gateway/sandboxing

### Sandbox シークレットポリシー

sandbox コンテナに注入するシークレットはホワイトリスト方式で管理する。

#### 判断基準（2条件の AND）

1. **必要性**: sandbox 内のツール実行で必要であること
2. **スコープ**: read-only または限定スコープの API キーであること

#### 許可リスト（sandbox env に渡すもの）

| キー                        | 用途                  | スコープ              | 判断理由                                    |
| --------------------------- | --------------------- | --------------------- | ------------------------------------------- |
| `GITHUB_TOKEN` / `GH_TOKEN` | git clone, gh CLI     | repo read/write       | sandbox のコア操作に必須                    |
| `XAI_API_KEY`               | Grok API（X投稿取得） | read-only（x_search） | sandbox 内 curl で必要 + read-only スコープ |

#### 拒否リスト（絶対に sandbox に渡さないもの）

| キー                                 | 理由                                                 |
| ------------------------------------ | ---------------------------------------------------- |
| Telegram bot token                   | メッセージ送信権限を持つ。sandbox に不要             |
| Slack bot/app token                  | チャネル投稿・読み取り権限を持つ。sandbox に不要     |
| Gateway auth token                   | Gateway 管理権限。sandbox に渡すと自身を操作可能     |
| 1Password サービスアカウントトークン | 全シークレットへのアクセス権。sandbox に渡すのは論外 |

#### 新しいキーを追加するときのチェックリスト

1. sandbox 内のツール実行で本当に必要か？（Gateway 側で処理できないか）
2. キーのスコープは read-only or 限定的か？
3. 拒否リストに該当しないか？
4. `openclaw.docker.json.tmpl` の env + この許可リスト両方を更新したか？
