# ツール別設定ガイド

## Claude Code

### ファイル名

- `CLAUDE.md` を使用

### 階層構造

| メモリタイプ                   | 場所                                                        |
| ------------------------------ | ----------------------------------------------------------- |
| エンタープライズポリシー       | `/Library/Application Support/ClaudeCode/CLAUDE.md` (macOS) |
| プロジェクトメモリ             | `./CLAUDE.md` または `./.claude/CLAUDE.md`                  |
| プロジェクトルール             | `./.claude/rules/*.md`                                      |
| ユーザーメモリ                 | `~/.claude/CLAUDE.md`                                       |
| プロジェクトメモリ（ローカル） | `./CLAUDE.local.md`                                         |

### モジュラールール

`.claude/rules/` ディレクトリで指示を整理:

```
.claude/rules/
├── testing.md
├── api-design.md
└── frontend/
    ├── components.md
    └── styling.md
```

### パス固有ルール

YAMLフロントマターで特定ファイルにスコープ:

```markdown
---
paths:
  - "**/*.tsx"
  - "src/components/**/*"
---

# React コンポーネントルール

...
```

### インポート機能

他ファイルをインポート:

```markdown
@path/to/import
@~/.claude/personal-rules.md
```

---

## GitHub Copilot

### ファイル名

- `AGENTS.md` を使用

### 配置

- リポジトリルートに配置
- サブディレクトリにも配置可能（近いファイルが優先）

---

## Cursor

### ファイル名

- `.cursor/rules/*.md` または `AGENTS.md`

### Rules 配置

```
.cursor/rules/
├── general.md
├── testing.md
└── api.md
```

### 推奨構成

```markdown
# Commands

- `npm run build`: Build the project
- `npm run test`: Run tests

# Code style

- Use ES modules (import/export), not CommonJS
- See `components/Button.tsx` for canonical structure

# Workflow

- Always typecheck after making code changes
```

---

## Codex CLI (OpenAI)

### ファイル名

- `AGENTS.md` を使用

### 配置

- リポジトリルートに配置
- モノレポでは各パッケージにも配置可能

---

## Gemini CLI

### ファイル名

- `AGENTS.md` を使用

### 設定ファイル

`.gemini/settings.json`:

```json
{
  "contextFileName": "AGENTS.md"
}
```

---

## Aider

### ファイル名

- `AGENTS.md` を使用

### 設定ファイル

`.aider.conf.yml`:

```yaml
read: AGENTS.md
```

---

## Zed

### ファイル名

- `AGENTS.md` を使用
- `.zed/rules.md` も対応

---

## 互換性確保

### シンボリックリンクの活用

複数エージェントに対応するため:

```bash
# AGENTS.md をメインとして CLAUDE.md をリンク
ln -s AGENTS.md CLAUDE.md

# または CLAUDE.md をメインとして AGENTS.md をリンク
ln -s CLAUDE.md AGENTS.md
```

### マイグレーション

既存ファイルの移行:

```bash
# AGENT.md → AGENTS.md への移行
mv AGENT.md AGENTS.md && ln -s AGENTS.md AGENT.md
```

---

## ツール別推奨設定まとめ

| ツール            | ファイル            | 追加設定              |
| ----------------- | ------------------- | --------------------- |
| Claude Code       | CLAUDE.md           | .claude/rules/\*.md   |
| GitHub Copilot    | AGENTS.md           | -                     |
| Cursor            | .cursor/rules/\*.md | AGENTS.md も対応      |
| Codex CLI         | AGENTS.md           | -                     |
| Gemini CLI        | AGENTS.md           | .gemini/settings.json |
| Aider             | AGENTS.md           | .aider.conf.yml       |
| Zed               | AGENTS.md           | .zed/rules.md         |
| VS Code (Copilot) | AGENTS.md           | -                     |
| Windsurf          | AGENTS.md           | -                     |
| Devin             | AGENTS.md           | -                     |
