# nix/modules/editors/nvim: Neovim 設定

## 管理対象

- `default.nix`: Home Manager の設定と Lua の配置
- `init.lua`: エディタの基本設定・起動処理
- `plugins.nix`: プラグインの導入・設定の呼び出し、Tree-sitter の言語一覧
- `lua/plugins/*.lua`: プラグインごとの Lua 設定（読み込み時に各プラグインの `setup()` を直接実行）
- `lua/config/*.lua`: 補助機能
- `lua/config/lsp.lua`: 共通 LSP 処理と整形に必要な設定

## 変更ルール

- 設定・プラグインは Home Manager が管理し、chezmoi で二重配布しない。
- プラグイン設定は公式例に沿った `require("plugin").setup(...)` とキー登録を記載する。設定を適用するだけの `local M` / `M.setup()` は作らず、`plugins.nix` から `require("plugins.<name>")` で読み込む。関数を公開する `lua/config/` のモジュールはこの対象外。
- プラグインのグローバルキーは各ファイルの `local keys = { ... }` にまとめ、末尾のループで `vim.keymap.set(key.mode or "n", key[1], key[2], { desc = key.desc })` を呼ぶ。バッファ・ウインドウ内のキーはプラグイン専用の設定に残す。グローバルキーのないファイルには空の一覧やループを追加しない。
- Neovim 本体・プラグインはこのディレクトリに直接宣言し、パッケージカタログを参照しない。
- LSP・整形ツールは `../../lsp.nix` の Home Manager module が通常の PATH に導入する。内部 PATH を追加しない。
- plugin 追加時は起動速度への影響を確認し、キーマップ衝突を避ける。
- 最低 Neovim 0.12。標準 LSP・補完・snippet・Tree-sitter API を使う。
- サーバー定義は nvim-lspconfig の標準設定を使い、個人環境向けの差分を追加しない。
- Tree-sitter は `nvim-treesitter.withPlugins` で対象言語を指定し、実行時のダウンロードを追加しない。
- 検証コマンドは `docs/chezmoi/neovim.md` を参照する。
