# nix/modules/editors/nvim: Neovim 設定

## 管理対象

- `default.nix`: Home Manager の設定・キー配列と leader・エディタの基本設定・イベント・ユーザーコマンド。構成側の `programs.nixvim.enable` に従う
- `lsp/<server>.nix` / `plugins/<name>.nix`: 対応するサーバー・プラグインの実行依存を通常の PATH へ導入
- `plugins/default.nix`: プラグイン別ファイルの読み込みと、package metadata に基づく共通の実行依存解決
- `plugins/<name>.nix`: 各プラグインの導入・設定・キー・専用 callback。Tree-sitter の言語一覧は `plugins/treesitter.nix`
- `lsp/default.nix`: サーバー別ファイルの読み込み、補完・LSP キーと保存時整形
- 基本 option・leader・静的なキーは Nixvim の `opts` / `globals` / `keymaps`、対応プラグインの設定は `plugins.<name>.settings` で宣言する。Lua の生成は Nixvim に任せ、独自の中間ファイルは作らない。autocmd・ユーザーコマンドも `autoCmd` / `userCommands` に宣言する
- `lsp/default.nix` が Neovim 標準の LSP 補完・キー・保存時整形を接続する。独自のサーバー選択は行わない

- PowerShell 本体はユーザー指定により `shells/powershell/` が所有する。`lsp/powershell_es.nix` はその有効化と package を参照し、Editor Services の設定を所有する。

## 変更ルール

- 設定・プラグインは Nixvim の Home Manager module が管理する。`wrapRc = true` / `impureRtp = false` で package に含め、XDG や chezmoi へ二重配布しない。
- `modes.nvim` のソースは `modes-nvim` flake input で管理し、`flake.lock` で固定する。
- 全プラグインの設定は Nixvim の `plugins.<name>.settings` に宣言する。標準 module がない Modes / Incline は同じ plugin factory を使う。callback は利用する設定に直接置き、共有が必要な関数や状態は所有する module のローカル変数にする。別の callback ファイルやグローバルな関数一覧は作らない。
- グローバルキーと LSP キーは `keymaps` / `lsp.keymaps` に宣言する。バッファ・ウインドウ内の動的なキーやイベントは plugin の `settings` / callback で扱う。
- Neovim 本体の有効化、package 選択、設定・連携・プラグインと専用の実行依存はこのディレクトリが所有する。LSP・整形ツール・toolchain を無関係な CLI の集約 module へ移さない。
- 補助コマンドは対応する `lsp/<server>.nix` / `plugins/<name>.nix` から通常の PATH に導入し、Neovim の内部 PATH を追加しない。
- plugin 追加時は起動速度への影響を確認し、キーマップ衝突を避ける。
- 最低 Neovim 0.12。標準 LSP・補完・snippet・Tree-sitter API を使う。
- サーバー定義は nvim-lspconfig の標準設定を使い、個人環境向けの差分を追加しない。
- Tree-sitter は `plugins.treesitter.grammarPackages` と設定した package の `builtGrammars` で対象言語を指定し、実行時のダウンロードを追加しない。
- 検証コマンドは `docs/chezmoi/neovim.md` を参照する。
