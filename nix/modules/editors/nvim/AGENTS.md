# nix/modules/editors/nvim: Neovim 設定

## 管理対象

- `home-manager.nix`: Home Manager の設定と Lua の配置。構成側の `programs.neovim.enable` に従う
- `runtime.home-manager.nix`: 補助 CLI・LSP・整形ツール・toolchain・プラグイン実行依存の導入
- `init.lua`: エディタの基本設定・起動処理
- `plugins.home-manager.nix`: プラグインの導入・設定の呼び出し、Tree-sitter の言語一覧
- `lua/plugins/*.lua`: プラグインごとの Lua 設定（読み込み時に各プラグインの `setup()` を直接実行）
- `lua/config/*.lua`: 補助機能
- `lua/config/lsp.lua`: 共通 LSP 処理と整形に必要な設定

## 変更ルール

- 設定・プラグインは Home Manager が管理し、chezmoi で二重配布しない。
- `modes.nvim` / `devcontainer-cli.nvim` のソースは `modes-nvim` / `devcontainer-cli-nvim` flake input で管理し、`flake.lock` で固定する。
- プラグイン設定は公式例に沿った `require("plugin").setup(...)` とキー登録を記載する。設定を適用するだけの `local M` / `M.setup()` は作らず、`plugins.home-manager.nix` から `require("plugins.<name>")` で読み込む。関数を公開する `lua/config/` のモジュールはこの対象外。
- プラグインのグローバルキーは各ファイルの `local keys = { ... }` にまとめ、末尾のループで `vim.keymap.set(key.mode or "n", key[1], key[2], { desc = key.desc })` を呼ぶ。バッファ・ウインドウ内のキーはプラグイン専用の設定に残す。グローバルキーのないファイルには空の一覧やループを追加しない。
- Neovim 本体の有効化、package 選択、設定・連携・プラグインと専用の実行依存はこのディレクトリが所有する。LSP・整形ツール・toolchain を無関係な CLI の集約 module へ移さない。
- 補助コマンドは `runtime.home-manager.nix` から通常の PATH に導入し、Neovim の内部 PATH を追加しない。
- plugin 追加時は起動速度への影響を確認し、キーマップ衝突を避ける。
- 最低 Neovim 0.12。標準 LSP・補完・snippet・Tree-sitter API を使う。
- サーバー定義は nvim-lspconfig の標準設定を使い、個人環境向けの差分を追加しない。
- Tree-sitter は `nvim-treesitter.withPlugins` で対象言語を指定し、実行時のダウンロードを追加しない。
- 検証コマンドは `docs/chezmoi/neovim.md` を参照する。
