# chezmoi/dot_config/nvim: Neovim 設定

## 管理対象

- `init.lua`
- `lua/config/*.lua`
- `lua/plugins/*.lua`
- `after/lsp/*.lua`: サーバー別の設定差分
- `treesitter.json`: 全 OS 共通のパーサー言語一覧

## 変更ルール

- plugin 追加時は起動速度への影響を確認する。
- キーマップ衝突を避ける。
- lazy.nvim 前提の構成を維持する。
- 最低 Neovim 0.12。`vim.lsp.config` / `vim.lsp.enable`、標準補完・snippet・Tree-sitter API を使う。
- Nix ではパーサー／クエリを配布し、Neovim 内で installer をロードしない。
- 検証コマンド・OS 別導入条件は `docs/chezmoi/neovim.md` を参照する。
