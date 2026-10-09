# Codex CLI の npm パッケージ方針

## 採用方式

Codex CLI は Windows、WSL/NixOS、macOS のすべてで npm の
`@openai/codex` を使用する。Nix の package catalog には CLI の derivation を
登録せず、Nix は `nodejs`/`npm` を提供する責務に限定する。

Windows は `nix/packages/install/node.nix` の npm metadata を
`nix/packages/sets.nix` 経由で `windows/npm/packages.json` に生成し、
`Handler.Npm.ps1` がグローバルインストールと `codex --version` を検証する。
Linux、WSL、macOS は `scripts/sh/codex-npm.sh` を使い、
`$HOME/.local/npm` にユーザー権限でインストールする。

Node の配布 metadata は package/provider 選択と変更理由が異なるため `install/` に分離します。
責務境界は [パッケージ管理の分割方針](./package-management.md#分割の理由と編集先) を参照してください。

Codex のデスクトップアプリは別製品であり、Microsoft Store の AppX
`9PLM9XGG6VKS` として管理する。これは npm の Codex CLI とは統合しない。

## セットアップと更新

Unix の設定・agents・rules・hooks・指示ファイルは `nix/modules/codex/` の
Home Manager 標準 `programs.codex` が管理する。CLI の npm 導入は変更しない。
`mutableSettings = true` により `config.toml` は書込み可能なまま、アプリが追加した
UI 設定や project trust を保持して宣言値をマージする。宣言した配列は置換され、
宣言から削除した値は既存ファイルに残るので、不要な設定は別途削除する。
Windows の設定は引き続き chezmoi が管理し、Unix installer は chezmoi を呼ばない。

`[desktop]` の `worktree-auto-cleanup-enabled = true` と `worktree-keep-count = 15`
を宣言する。対象は Codex-managed worktree のみで、`Documents/codex` 内の通常の
プロジェクトやモデルデータを一律に削除する設定ではない。保護対象や snapshot は
[公式 cleanup](https://learn.chatgpt.com/docs/environments/git-worktrees) に従う。
既存 config が不正な TOML、または Nix store への symlink ならマージは失敗し、
上書きしない。認証ファイル・履歴・セッションは Home Manager の管理対象にしない。

設定のマージは [Home Manager の標準機能](https://nix-community.github.io/home-manager/options/home-manager/programs/codex.html#programscodexmutablesettings)
を使い、独自 cleanup timer や独自 config merger は追加しない。

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
