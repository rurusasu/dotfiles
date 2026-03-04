# chezmoi/editors/nvim: Neovim 設定

## 管理対象

- `init.lua`
- `lua/config/*.lua`
- `lua/plugins/init.lua`

## 変更ルール

- plugin 追加時は起動速度への影響を確認する。
- キーマップ衝突を避ける。
- lazy.nvim 前提の構成を維持する。
