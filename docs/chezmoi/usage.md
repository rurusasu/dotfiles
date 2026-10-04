# Chezmoi の使い方

## インストールと初回適用

リポジトリをクローンし、そのルートで OS に合う installer を使います。CLI の順序・依存関係は Taskfile と platform adapter が管理します。

```bash
# macOS / Linux / WSL
./install.sh
```

```powershell
# Windows
.\install.cmd
```

chezmoi のパッケージは `nix/packages/catalog/core.nix` で管理し、`nix/packages/sets.nix` を公開入口にします。共通 Nix パッケージは `nix/home/common.nix` が利用し、Windows は生成済み winget manifest を使います。配布と設定の変更理由を分ける方針は [パッケージ管理](../nix/package-management.md#分割の理由と編集先) を参照してください。

## クローン済み設定の更新

chezmoi のソースがリポジトリ全体ではなく **`chezmoi/`** であることを確認してください。

```bash
# リポジトリのルート。PowerShell でも同じコマンドを使用可能。
chezmoi init --source "$PWD/chezmoi"
chezmoi --source "$PWD/chezmoi" diff
chezmoi --source "$PWD/chezmoi" apply
```

`init` は設定テンプレートを再生成します。`apply` はファイルだけでなく対象の install/deploy スクリプトも実行するため、差分と対象を確認してから適用します。1Password・暗号化設定は [シークレット管理](./secrets.md) と [1Password](../1password/README.md) を参照してください。

`dotf chezmoi`（`task chezmoi`）は現在 WSL/Windows の相互呼び出しを含むため、macOS / Windows のない Linux では上記の直接コマンドを使います。

`chezmoi init rurusasu/dotfiles --source-path chezmoi` は使用しません。`--source-path` はサブディレクトリを値に取るオプションではありません。また、削除済みの `scripts/powershell/apply-chezmoi.ps1` を直接呼ぶ旧手順も使用しません。

## 配置方式

- `dot_config/git/` などの `dot_*` は chezmoi が直接配置します。
- `terminals/` などのカテゴリ別ファイルは `.chezmoiscripts/deploy/` の adapter が配置します。
- Neovim の設定は `nix/modules/nvim/` に置き、Home Manager が管理します。
- WezTerm は Windows 用の `chezmoi/terminals/wezterm/wezterm.lua` を直接編集します。macOS・NixOS・WSL は `nix/modules/terminals/wezterm/` の設定を Home Manager が配布します。

詳細は [ディレクトリ構造](./structure.md)、[Neovim](./neovim.md) を参照してください。実機反映後は対象アプリを再起動し、配置済みファイル・実際のキーバインドも確認します。
