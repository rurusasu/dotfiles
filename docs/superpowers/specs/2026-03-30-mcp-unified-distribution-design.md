# MCP サーバー統一配布システム設計

**日付:** 2026-03-30
**ステータス:** Approved
**対象リポジトリ:** dotfiles

## 概要

`mcp_servers.yaml` を拡張し、9 つの AI ツールに MCP サーバー設定を chezmoi から一元配布する。HTTP MCP サーバーを stdio-only ツールから利用する場合は `mcp-remote` で自動ブリッジする。

## 動機

- 現在 4 ツール (claude-code, codex, gemini, cursor) のみ対応
- Claude Code は `~/.claude/.claude.json` の `url` ベース MCP を読まない
- Claude Desktop, ChatGPT Desktop, VS Code, Windsurf, Zed のテンプレートがない
- ツール追加のたびに手動設定が必要

## データモデル

### `mcp_servers.yaml` 拡張

`transport` フィールドを追加。`supports` を 9 ツール ID に拡張。

```yaml
# HTTP MCP サーバー (Kind クラスタ内)
- name: superlocalmemory
  url: "http://localhost:3000/mcp"
  transport: http
  supports:
    - claude-code
    - claude-desktop
    - chatgpt
    - codex
    - gemini
    - cursor
    - vscode
    - windsurf
    - zed

# stdio MCP サーバー (Docker MCP SDK)
- name: tavily
  command: docker
  args: ["run", "-i", "--rm", "-e", "TAVILY_API_KEY", "mcp/tavily"]
  transport: stdio
  startup_timeout_sec: 60
  env:
    TAVILY_API_KEY: "${TAVILY_API_KEY}"
  op_env:
    TAVILY_API_KEY: "op://openclaw/TavilyUsedOpenclawPAT/credential"
  supports:
    - claude-code
    - codex
    - gemini
    - cursor
```

### ツール ID 一覧

| ID               | ツール            | 設定ファイル (Windows)                        |
| ---------------- | ----------------- | --------------------------------------------- |
| `claude-code`    | Claude Code CLI   | `~/.claude.json` (mcpServers)                 |
| `claude-desktop` | Claude Desktop    | `%APPDATA%/Claude/claude_desktop_config.json` |
| `chatgpt`        | ChatGPT Desktop   | 要確認（設定ファイルパス）                    |
| `codex`          | Codex CLI         | `~/.codex/config.toml`                        |
| `gemini`         | Gemini CLI        | `~/.gemini/settings.json`                     |
| `cursor`         | Cursor CLI        | `~/.cursor/cli-config.json`                   |
| `vscode`         | VS Code (Copilot) | ユーザー `settings.json` の `mcp` セクション  |
| `windsurf`       | Windsurf          | `~/.codeium/windsurf/mcp_config.json`         |
| `zed`            | Zed Editor        | `%APPDATA%/Zed/settings.json`                 |

## テンプレート展開ルール

### トランスポート自動変換

| サーバー transport | ツール HTTP 対応 | 出力形式                             |
| ------------------ | ---------------- | ------------------------------------ |
| `stdio`            | 全ツール         | `command` + `args` をそのまま出力    |
| `http`             | HTTP 対応        | ツール固有の URL 形式で出力          |
| `http`             | stdio-only       | `mcp-remote` ラッパーで stdio に変換 |

### HTTP 対応ツール

`claude-code`, `codex`, `gemini`, `cursor`, `vscode`, `windsurf`

これらは `url` フィールドを直接出力（ツールごとにフォーマットが異なる）。

### stdio-only ツール

`claude-desktop`, `chatgpt`, `zed`

`transport: http` のサーバーに対して以下を出力:

```json
{
  "command": "npx",
  "args": ["-y", "mcp-remote", "http://localhost:3000/mcp"]
}
```

## ツール別テンプレート設計

### 1. Claude Code (`claude-code`)

**設定先:** `~/.claude.json` の `mcpServers`
**方法:** chezmoi `run_onchange` スクリプトで `claude mcp add` を実行
**理由:** `~/.claude.json` は動的データ (OAuth, 起動回数等) を含むためテンプレートで丸ごと管理不可

```bash
# .chezmoiscripts/deploy/llms/run_onchange_deploy_claude_code_mcp.sh.tmpl
{{- range .mcp_servers }}
{{- if has "claude-code" .supports }}
{{- if eq (default "stdio" .transport) "http" }}
claude mcp add --transport http "{{ .name }}" "{{ .url }}" -s user 2>/dev/null || true
{{- else }}
claude mcp add "{{ .name }}" -- {{ .command }} {{ range .args }}{{ . }} {{ end }}-s user 2>/dev/null || true
{{- end }}
{{- end }}
{{- end }}
```

### 2. Claude Desktop (`claude-desktop`)

**設定先:** `%APPDATA%/Claude/claude_desktop_config.json`
**方法:** chezmoi テンプレート
**形式:** `mcpServers` オブジェクト (stdio のみ)

```json
{
  "mcpServers": {
    "superlocalmemory": {
      "command": "npx",
      "args": ["-y", "mcp-remote", "http://localhost:3000/mcp"]
    },
    "context7": {
      "command": "pnpm",
      "args": ["dlx", "@upstash/context7-mcp@latest"]
    }
  }
}
```

### 3. ChatGPT Desktop (`chatgpt`)

**設定先:** 要調査（設定ファイルパスの確認が必要）
**方法:** chezmoi テンプレート
**形式:** stdio ベース

### 4. Codex CLI (`codex`)

**設定先:** `~/.codex/config.toml`
**方法:** 既存テンプレート修正
**形式:**

- stdio: `command = "..."`, `args = [...]`
- http: `url = "..."`

### 5. Gemini CLI (`gemini`)

**設定先:** `~/.gemini/settings.json`
**方法:** 既存テンプレート修正
**形式:**

- stdio: `"command": "..."`, `"args": [...]`
- http: `"url": "..."`

### 6. Cursor CLI (`cursor`)

**設定先:** `~/.cursor/cli-config.json`
**方法:** 既存テンプレート修正
**形式:** Gemini と同じ

### 7. VS Code (`vscode`)

**設定先:** ユーザー `settings.json` の `mcp.servers` セクション
**方法:** chezmoi テンプレート（`editors/vscode/settings.json` に追加）
**形式:**

```json
{
  "mcp": {
    "servers": {
      "superlocalmemory": {
        "type": "http",
        "url": "http://localhost:3000/mcp"
      },
      "context7": {
        "type": "stdio",
        "command": "pnpm",
        "args": ["dlx", "@upstash/context7-mcp@latest"]
      }
    }
  }
}
```

### 8. Windsurf (`windsurf`)

**設定先:** `~/.codeium/windsurf/mcp_config.json`
**方法:** chezmoi テンプレート新規
**形式:**

```json
{
  "mcpServers": {
    "superlocalmemory": {
      "serverUrl": "http://localhost:3000/mcp"
    },
    "context7": {
      "command": "pnpm",
      "args": ["dlx", "@upstash/context7-mcp@latest"]
    }
  }
}
```

### 9. Zed (`zed`)

**設定先:** `%APPDATA%/Zed/settings.json` の `context_servers`
**方法:** 既存テンプレート修正（`editors/zed/settings.json`）
**形式:**

```json
{
  "context_servers": {
    "superlocalmemory": {
      "source": "custom",
      "command": "npx",
      "args": ["-y", "mcp-remote", "http://localhost:3000/mcp"]
    },
    "context7": {
      "source": "custom",
      "command": "pnpm",
      "args": ["dlx", "@upstash/context7-mcp@latest"]
    }
  }
}
```

## 既存テンプレートの移行

### supports ID の変更

| 旧 ID    | 新 ID               |
| -------- | ------------------- |
| `claude` | `claude-code`       |
| `codex`  | `codex` (変更なし)  |
| `cursor` | `cursor` (変更なし) |
| `gemini` | `gemini` (変更なし) |

既存テンプレートの `has "claude"` → `has "claude-code"` に変更。

### transport フィールド

既存サーバー (`command` あり) はデフォルト `stdio`。明示不要だが、`url` のみのサーバーは `transport: http` が必要。

後方互換: `transport` フィールドがないサーバーは以下で判定:

- `url` あり + `command` なし → `http`
- `command` あり → `stdio`
- `url` + `command` 両方あり → ツールに応じて使い分け（既存動作を維持）

## 変更対象ファイル

### 新規作成

- `chezmoi/dot_config/claude-desktop/claude_desktop_config.json.tmpl`
- `chezmoi/dot_codeium/windsurf/mcp_config.json.tmpl`
- `chezmoi/.chezmoiscripts/deploy/llms/run_onchange_deploy_claude_code_mcp.sh.tmpl`
- `chezmoi/.chezmoiscripts/deploy/llms/run_onchange_deploy_claude_code_mcp.ps1.tmpl`

### 変更

- `chezmoi/.chezmoidata/mcp_servers.yaml` — `transport` フィールド追加、`supports` ID 拡張
- `chezmoi/dot_claude/dot_claude.json.tmpl` — `has "claude"` → `has "claude-code"`
- `chezmoi/dot_codex/config.toml.tmpl` — 変更なし（ID 同じ）
- `chezmoi/dot_cursor/cli-config.json.tmpl` — 変更なし（ID 同じ）
- `chezmoi/dot_gemini/settings.json.tmpl` — 変更なし（ID 同じ）
- `chezmoi/editors/vscode/settings.json` → `.tmpl` 化して `mcp.servers` セクション追加
- `chezmoi/editors/zed/settings.json` → `.tmpl` 化して `context_servers` セクション追加

### ChatGPT Desktop

設定ファイルのパスとフォーマットが未確認。実装フェーズで調査し、テンプレートを作成する。

## テスト

### 既存テスト修正

- `ChezmoiTemplate.Tests.ps1` の `onepasswordRead` ガードテストを維持
- Docker MCP SDK テストを維持

### 新規テスト

- 各テンプレートが正しい JSON/TOML を出力するか検証
- `transport: http` + stdio-only ツールで `mcp-remote` ラッパーが生成されるか検証
- `supports` フィルタが正しく動作するか検証
- Claude Code の `run_onchange` スクリプトが冪等に動作するか検証

## 実装フェーズ

### Phase 1: データモデル拡張

- `mcp_servers.yaml` に `transport` フィールド追加
- `supports` ID を新体系に移行
- 既存テンプレート (claude, codex, cursor, gemini) を新 ID に対応

### Phase 2: 新規テンプレート作成

- Claude Desktop テンプレート
- Windsurf テンプレート
- VS Code settings.json テンプレート化
- Zed settings.json テンプレート化

### Phase 3: Claude Code run_onchange スクリプト

- `claude mcp add` ベースのデプロイスクリプト作成
- 冪等性の確認

### Phase 4: ChatGPT Desktop

- 設定ファイルパスの調査
- テンプレート作成

### Phase 5: テスト

- 全テンプレートの出力検証テスト
- `chezmoi apply` → 各ツールでの接続確認
