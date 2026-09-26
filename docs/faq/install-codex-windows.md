# install.cmd 実行後に Codex CLI が使えない場合

## 概要

Codex CLI は Windows でも npm の `@openai/codex` からインストールする。
Microsoft Store の Codex デスクトップアプリは別製品なので、CLI の確認に
winget の `OpenAI.Codex` CLI package は使わない。

## 手動セットアップ

Node.js/npm が利用できる PowerShell で実行する。

```powershell
npm install -g @openai/codex@latest
codex --version
codex update
```

`codex` が見つからない場合は、npm のグローバル prefix と PATH を確認する。

```powershell
npm prefix --global
npm bin --global
Get-Command codex -All
```

新しい PowerShell を開いても解決できない場合は、表示された npm の prefix 配下
（通常は `%APPDATA%\npm`）をユーザー PATH に追加してから再実行する。

## dotfiles のインストールフロー

| 段階 | 役割 | Codex CLI との関係 |
| --- | --- | --- |
| install.cmd Phase 1 | npm handler | `@openai/codex` をグローバルインストール |
| install.cmd Phase 2 | Chezmoi | `~/.codex/` の設定と skills を展開 |
| 新しい PowerShell | PATH の再読込 | npm の `codex` を解決 |

確認コマンド:

```powershell
npm list --global --depth=0 @openai/codex
codex --version
codex update
```

設定だけ再適用する場合は、従来どおり chezmoi を実行する。

```powershell
chezmoi init rurusasu/dotfiles --source-path chezmoi
chezmoi apply
```
