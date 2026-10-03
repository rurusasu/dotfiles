# nix/modules/nvim: Neovim 設定

## 管理対象

- `default.nix`: Home Manager の設定と Lua の配置
- `init.lua`: エディタの基本設定・起動処理
- `plugins.nix`: プラグインの導入・設定の呼び出し、Tree-sitter の言語一覧
- `lua/plugins/*.lua`: プラグインごとの Lua 設定（`setup()` で適用）
- `lua/config/*.lua`: 補助機能
- `lua/config/lsp.lua`: 共通 LSP 処理と整形に必要な設定

## 変更ルール

- 設定・プラグインは Home Manager が管理し、chezmoi で二重配布しない。
- plugin 追加時は起動速度への影響を確認し、キーマップ衝突を避ける。
- 最低 Neovim 0.12。標準 LSP・補完・snippet・Tree-sitter API を使う。
- サーバー定義は nvim-lspconfig の標準設定を使い、個人環境向けの差分を追加しない。
- Tree-sitter は `nvim-treesitter.withPlugins` で対象言語を指定し、実行時のダウンロードを追加しない。
- 検証コマンドは `docs/chezmoi/neovim.md` を参照する。
