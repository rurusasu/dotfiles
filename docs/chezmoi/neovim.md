# Neovim の設定・導入・検証

## 要件と責務

最低 Neovim **0.12**。更新時は `nvim --version` と `:checkhealth vim.lsp` を確認します。

- Neovim 本体の有効化・基本設定・イベント・ユーザーコマンド: `nix/modules/editors/nvim/default.nix`
- 補助コマンド・LSP・整形ツール・toolchain・プラグイン実行依存の導入: `nix/modules/editors/nvim/lsp/<server>.nix` と `plugins/<name>.nix`
- LSP の有効化・サーバー別設定・実行依存: `lsp/<server>.nix`。共通の補完・キー・保存時整形は `lsp/default.nix`
- プラグイン別ファイルの読み込み: `nix/modules/editors/nvim/plugins/default.nix`
- 各プラグインの導入・設定・キー: `plugins/<name>.nix`。Tree-sitter の言語一覧は `plugins/treesitter.nix`
- 設定値・キー・autocmd・ユーザーコマンド: Nixvim の標準 option
- Snacks の PDF プレビュー・ghq 連携・smart 検索: `plugins/snacks.nix`
- 基本キー配列・leader: `default.nix` の `programs.nixvim.keymaps` / `globals`。プラグインのキーは各 `plugins/<name>.nix`
- Marp の導入・共通設定・プレビュー起動と Neovim 連携: `nix/modules/marp/default.nix`

package データ、配布方式、エディタ設定を変更理由ごとに分けます。
共通方針は [パッケージ管理の分割理由](../nix/package-management.md#分割の理由と編集先) を参照してください。

[Nixvim の Home Manager module](https://nix-community.github.io/nixvim/user-guide/install.html) を使い、構成側の `programs.nixvim.enable` で有効化します。`nixvim` input は共通の `nixpkgs` に follows し、`nixpkgs.useGlobalPackages = true` で同じ package set を使います。Neovim 本体は `pkgs.neovim-unwrapped`、補助コマンド・LSP・整形ツール・toolchain は各 `lsp/<server>.nix` と `plugins/<name>.nix` が通常のユーザー PATH へ導入します。

設定値は `opts` / `globals`、キーは `keymaps`、イベントは `autoCmd`、コマンドは `userCommands`、全プラグインの設定は `plugins.<name>.settings` に宣言します。Modes / Incline も Nixvim の標準 plugin factory で型付き option を定義します。Lua の生成・初期化順序・配布は Nixvim が担当し、PDF preview・ウインドウ操作・整形対象の選択などの callback は利用する設定に直接置きます。共有する関数や状態は、その設定を所有する module 内のローカル変数として定義します。

### 設定の配布

`wrapRc = true` / `impureRtp = false` により、Nixvim が設定と補助 Lua を package の runtime に含めます。個別の `.lua` ソースや設定ディレクトリは配布せず、独自の `init.lua` 生成、共通キー用の中間ファイル、XDG への二重配布も行いません。`nixvim-print-init` で生成された起動設定を確認できます。NixOS-WSL も同じ設定を使い、変更は `./install.sh` で反映して Neovim を再起動します。

## Tree-sitter は何が必要か

構文解析とハイライトの実行は Neovim 本体の `vim.treesitter.start()` で行います。したがって、それだけのために nvim-treesitter の Lua プラグインをロードする必要はありません。ただし **言語ごとのパーサーバイナリと対応クエリ** は必要です。Neovim 同梱の少数言語だけでは Python、Nix、TSX などをカバーできません。[Neovim 公式](https://neovim.io/doc/user/treesitter/)

`programs.nixvim.plugins.treesitter.grammarPackages` に対象言語を指定します。パーサーは設定した Tree-sitter package の `builtGrammars` から取得し、対応クエリと組み合わせます。実行時のダウンロード・ビルドは行いません。

プラグインの `setup()` は Nixvim が適用します。callback も Nix の `settings` / `keymaps` / `autoCmd` に宣言します。Sidekick は CLI 連携を使い、未構成の Copilot NES は無効にします。プラグインは Nix の再反映で更新します。

Nix は継承先のクエリ（ecma、jsx、html_tags など）も閉包に含めます。「プラグインコードをロードしない」と「Nix store に nvim-treesitter 由来のパッケージが一切存在しない」は別です。ファイルタイプ `sh` / `javascriptreact` / `typescriptreact` は対応する grammar に明示登録します。

`modes.nvim` のソースは flake input の `modes-nvim` で管理します。更新は `nix flake update modes-nvim` と通常の Nix 反映を使います。

インデントは標準 filetype indent / smartindent を使います。旧 nvim-treesitter の `indent = { enable = true }` と完全に同一の動作ではありません。パーサー未導入時は従来 syntax にフォールバックしますが、ABI 不一致や壊れた query は隠しません。

## LSP

`plugins/lspconfig.nix` が nvim-lspconfig の `lsp/*.lua` を有効にします。各 `lsp/<server>.nix` が `lsp.servers.<name>` と実行依存を管理し、起動・補完・LSP キー登録は Nixvim に任せます。`cmd` / `root_dir` の独自定義やサーバー選択は行いません。`package = null` は各サーバーのファイルが通常のユーザー PATH に導入する package を使う指定です。

| 対象                   | サーバー／実行ファイル | 補足                                                         |
| ---------------------- | ---------------------- | ------------------------------------------------------------ |
| Nix                    | nixd                   | nixfmt による保存時整形                                      |
| Go                     | gopls                  | Go toolchain と gopls を導入                                 |
| Rust                   | rust-analyzer          | rustup・rustfmt と rust-analyzer を導入                      |
| C#                     | csharp-ls              | Roslyn ベース。.NET SDK 10、保存時整形                       |
| JS / TS                | tsc (TS7+)             | 上流の TS7 LSP 定義に固定                                    |
| JS / TS lint           | oxlint                 | 上流の project-local cmd、設定ファイル検出、Astro 対応を維持 |
| YAML                   | yaml-language-server   | Nix                                                          |
| TOML                   | taplo                  | Nix                                                          |
| Shell                  | bash-language-server   | Nix                                                          |
| Lua                    | lua-language-server    | Lua LS と StyLua を導入                                      |
| Markdown               | marksman               | Nix                                                          |
| Python lint/format     | ruff                   | hover は ty に任せる                                         |
| Python type/completion | ty                     | ty.toml / pyproject.toml などを root とする                  |

TypeScript は `tsc` のみを有効化します。独自のプロジェクト別選択、旧サーバーへのフォールバック、互換用の設定は持ちません。サーバーの root 判定・起動引数は nvim-lspconfig の上流定義に従います。

### TS7 終了時の未解決警告

2026-09-06 の tsc 7.0.2 / Neovim 0.12.5 では、正常な shutdown 要求後にも `context canceled` と exit code 1 を観測しました。dotfiles をロードせず、上流 tsc 設定だけを有効化した隔離プローブでも再現しています。接続・補完は成功していますが、終了コードまで正常とはしていません。通知を隠す workaround は追加しません。[Microsoft の過去の類似ログ](https://github.com/microsoft/typescript-go/issues/3026) は参考であり、同一原因や現在の修正予定を証明するものではありません。

拡張子などから判定した filetype に応じて、設定済み・実行可能な LSP を自動起動します。保存前と手動 `Space f` の整形には、Neovim 標準の `vim.lsp.buf.format` を使います。独自のサーバー選択や優先順位は指定しません。Nix の nixfmt など、必要な外部コマンドは対応するサーバーのファイルが導入します。

各サーバーの解析・整形動作は上流の設定に従います。dotfiles 側で Clippy の実行条件を追加したり、保存時にテストを起動したりはしません。

個人の `~/.dotfiles` や特定ホストの NixOS options を補完対象にする設定は追加しません。Nix フォーマットには nixfmt が別途必要です。

## 標準補完・キー

nvim-cmp、cmp source 群、LuaSnip、friendly-snippets は使用しません。LSP の snippet は標準 `vim.snippet` で展開・移動します。LuaSnip 独自 snippet 集の互換は提供しません。

| 操作                                       | キー                                             |
| ------------------------------------------ | ------------------------------------------------ |
| LSP 補完                                   | `Ctrl+X Ctrl+O`、または届く端末では `Ctrl+Space` |
| バッファ語補完                             | `Ctrl+N/P`                                       |
| パス補完                                   | `Ctrl+X Ctrl+F`                                  |
| 候補選択／snippet 移動                     | `Tab / Shift+Tab`                                |
| 選択候補確定                               | `Enter` / `Ctrl+Y`                               |
| 未選択時の改行                             | `Enter`（先頭候補を勝手に確定しない）            |
| 補完キャンセル                             | `Ctrl+E`                                         |
| コメント                                   | `gc` / `gcc`                                     |
| 参照・rename・action・implementation・type | `grr / grn / gra / gri / grt`                    |
| 定義・hover                                | `gd` / `K`                                       |

標準の自動補完はサーバーの trigger character に従います。cmp のようにあらゆる文字入力で複数 source を同時検索する構成ではありません。`completeopt=menu,menuone,noselect,popup` により説明 popup と明示選択を使います。autopairs の Enter 上書きを無効にし、insert-mode の `Ctrl+Y` を redo で奪わないようにしています。

Herdr の terminal prefix も `Ctrl+Space` です。Neovim に届かない環境では `Ctrl+X Ctrl+O` を使ってください。Ghostty の分割・タブ操作キーは割り当てず、ターミナル内の区画は Herdr で管理します。

`-` は現在のファイルの親ディレクトリを Oil で開き、`Space d e` は診断を表示します。`Space Space` は fuzzy file search、`Space g g` は Lazygit、`Space s g` はファイル検索です。Oil 内は標準キーマップを使い、`Esc` に標準の `actions.close` だけを追加しています。バッファに名前を追加・編集したり、行を削除・移動したりして、`:w` でファイル操作を反映します。ディレクトリの追加は名前の末尾に `/` を付けます。ヘルプは `g?`、閉じる操作は `Esc` / `Ctrl+C` です。削除は trash に送ります。Sidekick を含むキー一覧は [キーバインド](./keybindings.md) を参照してください。

## Marp

`programs.marp.enable` で nixpkgs の Marp CLI と `marp-preview` を導入します。
共通設定は `programs.marp.settings`、ポートは `programs.marp.preview.port`（既定 8080）で管理します。
設定は `~/.config/marp/config.json` にも公開し、`marp-preview` が Nix store の同じ設定を使います。

CLI は `marp-preview ./slides` でプレビューサーバーを起動します。`package.json` や Bun は不要です。
Neovim では Markdown を保存して `Space marp` または `:MarpPreview` を実行すると、Snacks の下部ターミナルでファイルのあるディレクトリを配信し、準備完了後に既定ブラウザで開きます。
名前のないバッファでは現在の作業ディレクトリを使います。停止は `:MarpStop`、状態確認は `:MarpStatus` です。
通常の `marp` にも同じ共通設定を適用します。設定は Nix の属性セットで宣言し、JSON ファイルを手書きする必要はありません。

## 画像・ターミナル

作業ディレクトリの OSC 7 通知は `default.nix` の `autoCmd` が `vim.api.nvim_ui_send` で送信します。Oil で表示中のディレクトリの通知は `plugins/oil.nix` が管理します。

Snacks は端末の画像対応を自動判定します。PDF は公式の [`picker.preview` と `picker.config`](https://github.com/folke/snacks.nvim/blob/main/docs/picker.md#️-config) で Poppler の変換処理を指定し、通常のファイル表示とソース別の専用プレビューを維持します。`VimEnter` での内部関数の差し替えは行いません。外部プロセスは `vim.system` で終了コード・10秒上限を確認します。ただし変換待ちは同期なので、大きな PDF の UI 停止を完全には解消していません。

Snacks の terminal と Sidekick の CLI ペインは `wrap` を有効にして横方向の view 移動を禁止し、縦スクロールだけを許可します。`termopen()` と Sidekick の scrollback が使う `nvim_open_term()` は `wrap` を false に戻すため、terminal / buffer の開始後に再適用します。

leader の Space は terminal mode のマッピングに使いません。`Space` で始まる terminal mode のマッピングがあると、shell へ送る space が `timeoutlen` まで確定待ちになり、入力が反映されていないように見えます。Snacks terminal の toggle は normal mode の `Space t t` / `Space t f` のみとし、terminal 内からは `<C-q>`（または `<C-\><C-n>`）で terminal mode を抜けてから切り替えます。`<C-q>` は `default.nix` の terminal mode 全体のマッピングで、Snacks 既定の `<Esc><Esc>` は `term_normal = false` により無効化しています。Esc は常に shell / CLI へ渡ります。

floating terminal は Snacks の標準機能を使います。`Space t f` で開閉し、隠しても同じターミナルを再表示できます。
独自の位置・サイズ保存、比率の永続化、リサイズ時の再生成は行いません。表示とリサイズは Snacks に任せます。
terminal の表示設定は `globals.dotfiles_terminal_options` が所有します。

## 検証

リポジトリのルートから実行します。作業ツリーの未追跡ファイルを含めて検証する場合は `path:.`、コミット済み checkout は通常の `.` を使えます。

```bash
nix build path:.#checks.aarch64-darwin.neovim-native --no-link
# Linux x86_64: checks.x86_64-linux.neovim-native
task test:bash
```

実 LSP テストは設定済み Nixvim と PATH 上の ty・ruff・TS7 の tsc を使います。上流の起動定義を調べる場合は `:lua vim.print(vim.api.nvim_get_runtime_file('lsp/tsc.lua', false))` で確認できます。テストは一時バッファを使い、プロジェクトファイルを保存しません。

```bash
nvim --headless -i NONE \
  -c 'lua local ok, err = pcall(dofile, "nix/tests/build/modules/editors/nvim/lsp-integration.lua"); if not ok then print(err); vim.cmd("cquit 1") end' \
  -c 'qa!'
```

全 plugin の起動テストは `neovim-native` に含まれます。一時 HOME / XDG 環境で、本番と同じ Nixvim package を通常起動します。テスト用の init や plugin pack は別途生成・配置しません。ホストへの反映は不要です。

headless テストでは terminal・画像の描画、IME・キーバインドの実入力を検証できません。これらと Linux の実機動作は対応環境で別途確認してください。
