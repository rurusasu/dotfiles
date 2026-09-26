# Codex CLI の npm パッケージ方針

## 採用方式

Codex CLI は Windows、WSL/NixOS、macOS のすべてで npm の
`@openai/codex` を使用する。Nix の package catalog には CLI の derivation を
登録せず、Nix は `nodejs`/`npm` を提供する責務に限定する。

Windows は `windows/npm/packages.json` を `nix/packages/sets.nix` から生成し、
`Handler.Npm.ps1` がグローバルインストールと `codex --version` を検証する。
Linux、WSL、macOS は `scripts/sh/codex-npm.sh` を使い、
`$HOME/.local/npm` にユーザー権限でインストールする。

Codex のデスクトップアプリは別製品であり、Microsoft Store の AppX
`9PLM9XGG6VKS` として管理する。これは npm の Codex CLI とは統合しない。

## セットアップと更新

通常の OS セットアップでは次の処理が自動実行される。

```bash
source scripts/sh/codex-npm.sh
dotfiles_install_codex_npm
```

Windows で手動実行する場合は次のコマンドを使う。

```powershell
npm install -g @openai/codex@latest
codex --version
codex update
```

npm のグローバル prefix は、Unix 系では既定で `$HOME/.local/npm`、Windows では
npm のユーザー prefix を使う。いずれも `codex` が PATH 上で解決できることを
セットアップ後に確認する。

## 検証

```bash
nix flake check --no-build --all-systems
codex --version
npm list --global --depth=0 @openai/codex
```

Windows の生成 manifest では Codex が winget に存在せず、npm manifest にだけ
存在することを確認する。デスクトップ AppX の検証は別の `OpenAI.Codex` launch
target 契約で維持する。
