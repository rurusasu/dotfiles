# install.cmd 実行後に Codex が使えない場合

## 概要

`D:\dotfiles\install.cmd` は **Phase 1** で winget により `OpenAI.Codex` をインストールします（管理者権限不要）。それでも `codex` コマンドが使えない場合の原因と対処法です。

## 想定される原因と対処

### 1. PATH が反映されていない（最も多い）

winget でインストールした後、**環境変数 PATH は「新しいターミナル」でないと更新されません**。install.cmd を実行した同じ CMD ウィンドウで `codex` を叩いても認識されないことがあります。

**対処:** ターミナルを一度閉じ、**新しい CMD または PowerShell を開いて**から `codex --version` を試してください。

### 2. Phase 1 で Winget が実行されていない

以下に当てはまると、Winget ハンドラーがスキップされ Codex がインストールされません。

- **winget が入っていない**  
  → [App Installer](https://apps.microsoft.com/detail/9nblggh4nns1)（Microsoft Store）をインストールするか、Windows を更新してください。
- **packages.json がない**  
  → `D:\dotfiles\windows\winget\packages.json` が存在するか確認してください。リポジトリをクローンした直後であれば存在するはずです。
- **install.cmd の作業ディレクトリ**  
  → `install.cmd` は「dotfiles のルート」で実行する前提です。`D:\dotfiles\install.cmd` のようにフルパスで実行するか、`cd D:\dotfiles` してから `.\install.cmd` を実行してください。

### 3. OpenAI.Codex のインストールに失敗している

Phase 1 のログに **「インストール失敗: OpenAI.Codex」** や **「インストール失敗 (exit=...)」** が出ている場合、winget 側で失敗しています。

**対処（手動インストール）:**

```powershell
# winget で再試行
winget install -e --id OpenAI.Codex --accept-package-agreements --accept-source-agreements
```

それでも失敗する場合は、npm でインストールしてください（Node.js が必要です）:

```powershell
npm install -g @openai/codex
```

### 4. Codex の「設定」が適用されていない

`codex` コマンドは使えるが、設定（`~/.codex/config.toml` やスキル）が欲しい場合は、**chezmoi** で dotfiles を適用する必要があります。install.cmd の Phase 2（管理者フェーズ）で Chezmoi ハンドラーが実行され、`~/.codex/` に設定が展開されます。

- **設定だけ適用したい場合:**
  ```powershell
  chezmoi init rurusasu/dotfiles --source-path chezmoi
  chezmoi apply
  ```
- または同梱スクリプト:
  ```powershell
  .\scripts\powershell\apply-chezmoi.ps1 -InstallChezmoi
  ```

## フローの整理

| 段階             | 役割                         | Codex との関係                      |
| ---------------- | ---------------------------- | ----------------------------------- |
| install.cmd      | Phase 1: Winget (user scope) | `OpenAI.Codex` をインストール       |
| install.cmd      | Phase 2: Chezmoi 等          | `~/.codex/` に config/skills を展開 |
| 新しいターミナル | PATH 反映                    | `codex` コマンドが使えるようになる  |

## 確認コマンド

```powershell
# Codex がインストールされているか
where.exe codex

# バージョン確認
codex --version

# winget でインストール済みか確認
winget list --id OpenAI.Codex
```

## 参考

- [AGENTS.md](../../AGENTS.md) - リポジトリ全体のセットアップ
- [Package + Config Workflow](../../AGENTS.md) - パッケージと設定の配置先
- [chezmoi/docs/](../../chezmoi/) - dotfiles（`~/.codex/` 含む）の管理
