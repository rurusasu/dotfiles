# Sandbox XAI API Key Injection & Secret Policy

**Date:** 2026-03-13
**Status:** Approved
**Scope:** OpenClaw sandbox シークレット注入の修正とポリシー策定

## Problem

OpenClaw の sandbox コンテナ（`openclaw-sandbox-common:bookworm-slim`）から xAI Grok API にアクセスできない。

### Root Cause

- `openclaw.docker.json.tmpl` の sandbox `env` に `XAI_API_KEY` が含まれていない
- `GITHUB_TOKEN` は渡されているが、`XAI_API_KEY` は漏れている
- AGENTS.md のドキュメントが実態と乖離（`network: "none"` と記載されているが実際は `"bridge"`）

### Impact

- sandbox 内の `shell_exec` で `curl + $XAI_API_KEY` による Grok API 呼び出しが失敗する
- X/Twitter 投稿の取得（`x_search`）が sandbox 経由で動作しない
- news skill, paper-intake 等の X 連携フローが機能しない

## Design

### 1. sandbox env に `XAI_API_KEY` を追加

`chezmoi/dot_openclaw/openclaw.docker.json.tmpl` の sandbox env セクション:

```json
"env": {
  "GITHUB_TOKEN": "@@GITHUB_TOKEN@@",
  "GH_TOKEN": "@@GITHUB_TOKEN@@",
  "XAI_API_KEY": "@@XAI_API_KEY@@",
  "PLAYWRIGHT_BROWSERS_PATH": "/root/.cache/ms-playwright",
  "GIT_CONFIG_COUNT": "1",
  "GIT_CONFIG_KEY_0": "url.https://x-access-token:@@GITHUB_TOKEN@@@github.com/.insteadOf",
  "GIT_CONFIG_VALUE_0": "https://github.com/"
}
```

`entrypoint.sh` の既存 sed（L41）が `@@XAI_API_KEY@@` を実際の値に置換するため、entrypoint への変更は不要。

### 2. Sandbox シークレットポリシー

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
4. `openclaw.docker.json.tmpl` の env + AGENTS.md の許可リスト両方を更新したか？

### 3. AGENTS.md ドキュメント修正

`network: "none"` の記述が3箇所に残っている。すべて修正する：

| 箇所                           | 現状                                                 | 修正後                                                                                                     |
| ------------------------------ | ---------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| L422（JSON コードブロック）    | `"network": "none"`                                  | `"network": "bridge"`                                                                                      |
| L432（セキュリティ箇条書き）   | `sandbox コンテナは network: "none"（外部通信不可）` | `sandbox コンテナは network: "bridge"（外部通信可能 — Playwright E2E、API 呼び出し等に必要）`              |
| L433（セキュリティ箇条書き）   | `sandbox コンテナにシークレットは注入されない`       | `sandbox コンテナに注入するシークレットは許可リストで管理する（下記「Sandbox シークレットポリシー」参照）` |
| L486（トラブルシューティング） | `docker.network: "none"` のためネットワーク不可      | 削除または `network: "bridge"` 前提の記述に書き換え                                                        |

さらに、シークレットポリシーセクション（許可リスト・拒否リスト・チェックリスト）を AGENTS.md の sandbox セクション末尾に追加する。

### 4. entrypoint.sh SANDBOX RULES heredoc 更新

`entrypoint.sh` L136-155 の SANDBOX RULES heredoc に `$XAI_API_KEY` が sandbox env で利用可能であることを追記する。

対象: L143 の後に追加:

```
- `$XAI_API_KEY` is available in the sandbox environment for Grok API calls (`x_search`). Use `curl` with this key for X/Twitter content retrieval.
```

注: L125（CODEX-FIRST RULES）は既に `$XAI_API_KEY` に言及しているため変更不要。

## Changed Files

| ファイル                                         | 変更内容                                                                                    |
| ------------------------------------------------ | ------------------------------------------------------------------------------------------- |
| `chezmoi/dot_openclaw/openclaw.docker.json.tmpl` | sandbox env に `"XAI_API_KEY": "@@XAI_API_KEY@@"` 追加（L79-86 の env ブロック）            |
| `docker/openclaw/AGENTS.md`                      | L422, L432, L433, L486 の `network: "none"` / シークレット記述修正 + ポリシーセクション追加 |
| `docker/openclaw/entrypoint.sh`                  | SANDBOX RULES heredoc（L136-155）に `$XAI_API_KEY` 利用可能の記載追加                       |
| `docker/openclaw/tests/test-entrypoint.sh`       | SANDBOX RULES の grep assert に `XAI_API_KEY` 言及を検証する assert 追加                    |

## Approach Selection

3つのアプローチを検討し、Approach A（最小 env 追加 + ドキュメント整備）を採用。

- **Approach A (採用)**: 既存 `@@PLACEHOLDER@@` パターンで env 1行追加 + ポリシードキュメント
- **Approach B (却下)**: env テンプレート自動展開 — 現状2キーで過剰設計
- **Approach C (却下)**: Gateway プロキシ方式 — アーキテクチャ変更が大きすぎる
