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

chezmoi のパッケージは `nix/packages/sets.nix` の catalog で管理します。共通 Nix パッケージは `nix/home/common.nix` が利用し、Windows は生成済み winget manifest を使います。

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

- `dot_config/nvim/` などの `dot_*` は chezmoi が直接配置します。
- `terminals/`、`editors/` などのカテゴリ別ファイルは `.chezmoiscripts/deploy/` の adapter が配置します。
- Windows の Neovim は `.config/nvim` を共有します。PowerShell の `XDG_CONFIG_HOME`、または `%LOCALAPPDATA%/nvim` の junction を通じて参照します。
- WezTerm の編集元は `chezmoi/terminals/wezterm/wezterm.lua` です。配布先の `~/.config/wezterm/wezterm.lua` と混同しないでください。

詳細は [ディレクトリ構造](./structure.md)、[Neovim](./neovim.md) を参照してください。実機反映後は対象アプリを再起動し、配置済みファイル・実際のキーバインドも確認します。
