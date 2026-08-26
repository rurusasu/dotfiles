---
name: create-agentsmd
description: AIコーディングエージェント向けの AGENTS.md / CLAUDE.md ファイルを作成・最適化するスキル。「AGENTS.mdを作成して」「CLAUDE.mdを書いて」「エージェント設定ファイルを作って」「プロジェクトのAI設定を最適化して」などのリクエストで使用。Claude Code, GitHub Copilot, Cursor, Codex CLI, Gemini CLI など複数のAIエージェントに対応した設定ファイルを生成する。
---

# AGENTS.md / CLAUDE.md 作成スキル

AIコーディングエージェント向けの設定ファイルを作成・最適化するスキル。

## 基本原則

### 1. 少ないほど良い

- **推奨行数: 60〜300行**（超えたら分割を検討）
- LLMは約150-200個の指示しか確実に従えない（インストラクション・バジェット）
- 指示が多いと全体が均一に無視されやすくなる

### 2. WHY / WHAT / HOW を定義

- **WHAT**: 技術スタック、プロジェクト構造、コードベースの全体像
- **WHY**: プロジェクトの目的、各ディレクトリの役割と設計思想
- **HOW**: テスト、型チェック、ビルドなど変更の検証方法

### 3. 普遍的に適用できる情報のみ

- すべてのタスクに関係する情報だけを記述
- タスク固有の情報は別ファイルに分離（Progressive Disclosure）

## 最小限テンプレート

```markdown
# AGENTS.md

## プロジェクト概要

[プロジェクトの一行説明]

## 技術スタック

- 言語: [言語名]
- フレームワーク: [フレームワーク名]
- パッケージマネージャー: [pnpm/npm/yarn/bun]

## コマンド

- ビルド: `[build command]`
- テスト: `[test command]`
- 型チェック: `[typecheck command]`

## ディレクトリ構成

- `src/`: ソースコード
- `tests/`: テストファイル
- `docs/`: ドキュメント
```

## 避けるべきパターン

### NG例

- コードスタイルガイドライン全文（→ linter/formatterに任せる）
- 変わりやすいファイルパス情報
- 古くなったドキュメント
- 矛盾する指示
- すべてのAPIエンドポイント詳細（→ 別ファイルに分離）

### リンターの仕事をさせない

コードスタイルは Biome, ESLint, Prettier などの決定論的ツールに任せる。LLMにスタイルチェックさせるのは非効率。

## モノレポ対応

二層構造で情報を階層化:

```
monorepo/
├── AGENTS.md              # ルートレベル（全体共通）
├── packages/
│   ├── frontend/
│   │   └── AGENTS.md      # フロントエンド固有
│   └── backend/
│       └── AGENTS.md      # バックエンド固有
└── docs/
    ├── TYPESCRIPT.md      # 詳細ドキュメント
    └── TESTING.md
```

## エージェント別対応

| エージェント   | ファイル名                               |
| -------------- | ---------------------------------------- |
| Claude Code    | CLAUDE.md                                |
| GitHub Copilot | AGENTS.md                                |
| Cursor         | .cursor/rules/\*.md または AGENTS.md     |
| Codex CLI      | AGENTS.md                                |
| Gemini CLI     | AGENTS.md (.gemini/settings.json で設定) |
| Aider          | AGENTS.md (.aider.conf.yml で設定)       |

### シンボリックリンクで互換性確保

```bash
ln -s AGENTS.md CLAUDE.md
```

## 作成手順

1. **プロジェクト分析**: 技術スタック、ディレクトリ構成、ビルドコマンドを確認
2. **最小限で開始**: WHY/WHAT/HOW の3点のみを記述
3. **段階的追加**: AIが繰り返し間違える箇所をルール化
4. **分割配置**: 300行を超えたら別ファイルに分離
5. **定期見直し**: プロジェクトの進化に合わせて更新

## 詳細リファレンス

- テンプレート集: [references/templates.md](references/templates.md)
- アンチパターン集: [references/antipatterns.md](references/antipatterns.md)
- ツール別設定: [references/tool-configs.md](references/tool-configs.md)
