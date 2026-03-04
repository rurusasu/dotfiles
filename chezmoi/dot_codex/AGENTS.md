> **Note:** Operational instructions for Codex should be placed in `chezmoi/dot_codex/AGENTS.override.md`. This `AGENTS.md` is solely for development documentation of this directory.

# Codex Configuration

This directory contains OpenAI Codex CLI configuration.

## Files

- `config.toml` - Codex CLI configuration
- `agents/` - Codex multi-agent role configs
  - [`agents/AGENTS.md`](./agents/AGENTS.md) - Sub-agent 作成/運用ベストプラクティス
  - `agents/fast_worker.toml` - Fast scoped implementation role
  - `agents/python_coding.toml` - Python implementation-only role
- `rules/` - Custom rules for Codex
  - `commands.rules` - Shell command rules
  - `nix.rules` - Nix-specific rules
  - `python.rules` - Python-specific rules
  - `safety.rules` - Safety rules
  - `starlark.rules` - Starlark/Bazel rules
- `AGENTS.override.md` - Override instructions for AI agents

## Deployment

Deployed to `~/.codex/` via chezmoi on all platforms.

## Installation

| Platform | Method     | Config                                                               |
| -------- | ---------- | -------------------------------------------------------------------- |
| NixOS    | Nix flakes | [`nix/core/cli.nix`](../../nix/core/cli.nix)                         |
| Windows  | winget     | [`windows/winget/packages.json`](../../windows/winget/packages.json) |

## MCP Servers

config.toml で設定している MCP サーバーと依存関係：

| Server   | 依存関係                 | 備考                                                           |
| -------- | ------------------------ | -------------------------------------------------------------- |
| context7 | Bun (bunx)               | `startup_timeout_sec` でタイムアウト調整可                     |
| tavily   | Bun (bunx) + API Key     | `TAVILY_API_KEY` を 1Password (`op read`) から自動注入         |
| drawio   | Bun (bunx)               | 起動が遅い環境では `startup_timeout_sec` を 30+ に設定         |
| linear   | なし (OAuth URL)         | 初回は `codex mcp login linear` が必要（PAT/env 自動注入不可） |
| sentry   | なし (OAuth URL)         | 初回は `codex mcp login sentry` が必要（PAT/env 自動注入不可） |
| serena   | uv (uvx)                 | Windows: `winget install astral-sh.uv`                         |

### トラブルシューティング

- **MCP タイムアウト**: `startup_timeout_sec` を増やす（`drawio` / `tavily` は 30 秒を推奨）
- **serena 起動失敗**: `uvx` コマンドが必要。uv をインストールする
- **linear/sentry ログインエラー**: `codex mcp login linear` / `codex mcp login sentry` を実行
- **Tavily 認証エラー**: `op` 連携で `TAVILY_API_KEY` がシェルに注入されているか確認する

## Configuration Notes

### 非推奨設定の対応

| 非推奨                          | 新しい設定            |
| ------------------------------- | --------------------- |
| `[features].web_search_request` | `web_search = "live"` |

### 開発中機能の警告抑制

`collab` や `elevated_windows_sandbox` 等の開発中機能を使用する場合：

```toml
suppress_unstable_features_warning = true
```
