# Neovim の設定・導入・検証

## 要件と責務

最低 Neovim **0.12**。更新時は `nvim --version` と `:checkhealth vim.lsp` を確認します。動作確認済み版と採否の根拠は [最新化調査](./neovim-modernization-audit.md) に記録します。

- 基本設定: `nix/modules/nvim/init.lua`
- 補助 Lua: `nix/modules/nvim/lua/`
- Neovim 本体と補助コマンドの導入: `nix/modules/nvim/default.nix`
- LSP・整形ツールの導入: `nix/modules/lsp.nix`
- Home Manager の起動設定: `nix/modules/nvim/default.nix`
- 共通 LSP 処理と整形設定: `nix/modules/nvim/lua/config/lsp.lua`
- プラグインの導入と Tree-sitter の言語一覧: `nix/modules/nvim/plugins.nix`
- プラグインの Lua 設定: `nix/modules/nvim/lua/plugins/*.lua`

package データ、配布方式、エディタ設定を変更理由ごとに分けます。
共通方針は [パッケージ管理の分割理由](../nix/package-management.md#分割の理由と編集先) を参照してください。

Neovim 関連ソフトウェアはパッケージカタログを使わず、Nixpkgs のパッケージを直接宣言します。共通の `nix/modules/lsp.nix` は `home.packages` を使い、通常の PATH に LSP・整形ツールを導入します。Darwin／NixOS の `default.nix` が Home Manager に読み込ませます。Neovim の内部 PATH は追加しません。プラグインの実行依存も通常のユーザー環境へ導入します。Windows の winget / pnpm では配布しません。

Neovim の設定とプラグインは Home Manager が管理し、chezmoi は配布しません。`default.nix` が `builtins.readFile ./init.lua` で基本設定を読み込み、プラグイン設定より先に実行します。実際の参照先は `:lua print(vim.fn.stdpath("config"))` で確認してください。非 Nix 環境向けの設定配布は行いません。

### 旧 chezmoi 設定からの初回移行

Home Manager の activation は、既存の `init.lua`、`lua/`、`after/lsp/` を同じ場所の `.pre-home-manager` 付きの名前へ退避してから、新しい `init.lua` と `lua` のリンクを配置します。たとえば `lua/` は `lua.pre-home-manager/` になります。ファイル内容と権限を保持し、削除やバックアップの上書きは行いません。旧 `after/lsp/` は上流 LSP 定義を上書きしないよう退避しますが、`after/ftplugin/` など無関係な `after/` の内容は残します。

全対象を `checkLinkTargets` より前に読み取り専用で検査します。実際の移動は `writeBoundary` より後、Home Manager の `linkGeneration` より前だけで行います。dry-run は空の `DRY_RUN` 変数を指定した場合も変更せず、再 activation は既存の Home Manager リンクとバックアップをそのまま扱います。移行は pinned Home Manager の `legacy` file activator 用で、グローバルなバックアップ設定は変更しません。

退避先が既にある場合、外部・壊れたシンボリックリンク、シンボリックリンクの親ディレクトリ、想定外のファイル種別は activation を停止します。`after/lsp` のリンクは Home Manager 管理のものも自動移行せず、実データの手動退避を要求します。リンクだけのバックアップは Nix の garbage collection 後に内容を失う可能性があるためです。この場合は表示された対象とバックアップを確認し、両方を別名で保管するなど手動で整理してから再実行してください。旧設定に戻す必要がある場合も、まず新しい Home Manager リンクを別の場所へ移し、退避済みデータを元の名前へ戻します。バックアップの自動削除はありません。

## Tree-sitter は何が必要か

構文解析とハイライトの実行は Neovim 本体の `vim.treesitter.start()` で行います。したがって、それだけのために nvim-treesitter の Lua プラグインをロードする必要はありません。ただし **言語ごとのパーサーバイナリと対応クエリ** は必要です。Neovim 同梱の少数言語だけでは Python、Nix、TSX などをカバーできません。[Neovim 公式](https://neovim.io/doc/user/treesitter/)

`nvim-treesitter.withPlugins` に対象言語を指定し、Home Manager の `programs.neovim.plugins` に直接登録します。独自の wrapper や環境変数は使用しません。パーサーと対応クエリのビルド・導入は標準の Nixpkgs / Home Manager の処理に任せます。

Home Manager が `init.lua` を生成し、基本設定の後に `plugins.nix` の順序で `require("plugins.<name>")` により各 `lua/plugins/*.lua` を読み込みます。各ファイルは公式例に沿ってプラグイン自身の `setup()` とキー登録を直接実行します。設定を適用するだけの `local M` / `M.setup()` は使いません。LSP は関数を公開する共通モジュール `lua/config/lsp.lua` の `setup()` を呼び出します。lazy.nvim による遅延読み込みと更新は使用しません。プラグインは Nix の再反映で更新します。

Nix は継承先のクエリ（ecma、jsx、html_tags など）も閉包に含めます。「プラグインコードをロードしない」と「Nix store に nvim-treesitter 由来のパッケージが一切存在しない」は別です。ファイルタイプ `sh` / `javascriptreact` / `typescriptreact` は対応する grammar に明示登録します。

データの更新は lock/package の更新と OS に合う Nix activation を使います。

インデントは標準 filetype indent / smartindent を使います。旧 nvim-treesitter の `indent = { enable = true }` と完全に同一の動作ではありません。パーサー未導入時は従来 syntax にフォールバックしますが、ABI 不一致や壊れた query は隠しません。

## LSP

nvim-lspconfig の標準サーバー定義を使い、起動は `vim.lsp.config` / `vim.lsp.enable`、共通処理は `LspAttach` で行います。個人環境向けの `after/lsp/` 設定は使用しません。整形に必要な Nix の nixfmt、YAML の整形有効化、Go の gofumpt は `lua/config/lsp.lua` に記載します。Mason やその PATH 補正は不要です。

| 対象                   | サーバー／実行ファイル     | 補足                                                         |
| ---------------------- | -------------------------- | ------------------------------------------------------------ |
| Nix                    | nixd                       | nixfmt による保存時整形                                      |
| Go                     | gopls                      | Nix で導入、gofumpt による整形                               |
| Rust                   | rust-analyzer              | 標準設定、保存時整形                                         |
| JS / TS                | tsc (TS7+) / ts_ls (TS5/6) | ネイティブ版優先、旧版の互換経路を維持                       |
| JS / TS lint           | oxlint                     | 上流の project-local cmd、設定ファイル検出、Astro 対応を維持 |
| YAML                   | yaml-language-server       | Nix                                                          |
| TOML                   | taplo                      | Nix                                                          |
| Shell                  | bash-language-server       | Nix                                                          |
| Lua                    | lua-language-server        | LuaJIT / vim globals                                         |
| Markdown               | marksman                   | Nix                                                          |
| Python lint/format     | ruff                       | hover は ty に任せる                                         |
| Python type/completion | ty                         | ty.toml / pyproject.toml などを root とする                  |

TypeScript 7 の `tsc --lsp --stdio` を優先し、使用できない環境では typescript-language-server へフォールバックします。両方を同じバッファへ起動しません。旧サーバーには TS5/6 の `tsserver.js` が必要です。global TypeScript を7に更新しただけでは旧サーバーの依存は満たせません。必要な旧プロジェクトには対応する TS5/6 を project-local に保持してください。TS 用の上流設定は Deno 判定も行います。

未導入 executable は起動対象から外し、後から別の project-local executable があるプロジェクトを開くケースも再評価します。実行ファイルが存在しても server 初期化やプロジェクト設定の成功までは保証しません。`:checkhealth vim.lsp`、`:messages`、`:lua vim.print(vim.lsp.get_clients({bufnr=0}))` を確認します。

選択順は project-local tsc → PATH tsc → project-local tsgo → PATH tsgo → local/PATH の従来サーバーです。バージョン確認は候補ごとに最大3秒。成功した選択は root ごとにセッション中固定し、不在はキャッシュしません。特定の旧機能のため従来サーバーを明示指定する場合は、LSP 起動前に `vim.g.dotfiles_typescript_server = "ts_ls"` を設定します。`"tsc"` を指定すると native のみに限定します。選択変更・依存更新後は再起動してください。

旧 nvim-lspconfig に tsc 定義がなくても、TS の filetypes を引き継いで無関係な言語へ起動しないようにしています。現行上流が持つ settings/commands は保持します。plugin 更新は nixpkgs の更新と Nix の再反映で行います。起動・配布の互換テストは現行 checkout と Nix 固定2.11.0の両方を使います。

### TS7 終了時の未解決警告

2026-09-06 の tsc 7.0.2 / Neovim 0.12.5 では、正常な shutdown 要求後にも `context canceled` と exit code 1 を観測しました。dotfiles をロードせず、上流 tsc 設定だけを有効化した隔離プローブでも再現しています。接続・補完は成功していますが、終了コードまで正常とはしていません。通知を隠す workaround は追加せず、必要なら上記の `ts_ls` 明示選択と TS5/6 を使ってください。[Microsoft の過去の類似ログ](https://github.com/microsoft/typescript-go/issues/3026) は参考であり、同一原因や現在の修正予定を証明するものではありません。

拡張子などから判定した filetype に応じて、設定済み・実行可能な LSP を自動起動します。整形対応の LSP が接続していれば、保存前に自動整形します（同期、上限3秒）。フォーマッターがないファイルでは何もしません。Python は Ruff、Rust は rust-analyzer に限定し、それ以外も接続した整形対応 LSP 一つだけを使って二重整形を避けます。手動 `Space f` も同じ選択を使います。LSP が使用する外部整形コマンド（Nix の nixfmt など）は別途導入が必要です。

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

この dotfiles の terminal prefix も `Ctrl+Space` です。Neovim に届かない環境では `Ctrl+X Ctrl+O` を使ってください。Sidekick・Oil・診断の最新キーは [キーバインド](./keybindings.md) を参照してください。

## 画像・ターミナル

Snacks は端末の画像対応を自動判定します。PDF は公式の [`picker.preview` と `picker.config`](https://github.com/folke/snacks.nvim/blob/main/docs/picker.md#️-config) で Poppler の変換処理を指定し、通常のファイル表示とソース別の専用プレビューを維持します。`VimEnter` での内部関数の差し替えは行いません。外部プロセスは `vim.system` で終了コード・10秒上限を確認します。ただし変換待ちは同期なので、大きな PDF の UI 停止を完全には解消していません。

Windows のカスタム floating terminal、Oil のドライブ一覧互換処理は維持します。0.12 更新だけを理由に、実機での根拠なく既存 workaround を撤去しません。

## 検証

リポジトリのルートから実行します。作業ツリーの未追跡ファイルを含めて検証する場合は `path:.`、コミット済み checkout は通常の `.` を使えます。

```bash
nix build path:.#checks.aarch64-darwin.neovim-native --no-link
# Linux x86_64: checks.x86_64-linux.neovim-native
python3 -m unittest discover -s tests/python -p test_neovim_migration.py -v
nix build path:.#checks.aarch64-darwin.package-provider-coverage --no-link
nix build path:.#winget-export --no-link --print-out-paths
nvim --headless -u NONE -i NONE -l tests/lua/nvim_modern_test.lua
bats tests/bash/bootstrap_entrypoint.bats
```

実 LSP テストには ty、ruff、TS7 の tsc と新しい nvim-lspconfig が必要です。例のパスは Home Manager が配置した nvim-lspconfig の Nix store パスに置き換えます。`:lua vim.print(vim.api.nvim_get_runtime_file('lsp/tsc.lua', false))` で確認できます。テストは一時バッファを使い、プロジェクトファイルを保存しません。

旧版の実 LSP テストでは TS5/6 と対応する typescript-language-server を PATH の先頭に置き、`DOTFILES_NVIM_TS_SERVER=ts_ls` を指定します（この環境変数はテストの期待値指定で、実設定の選択は上記の Lua global）。TS5.9.3＋従来サーバー5.3.0でも初期化・補完応答まで確認しました。routing テストはプロセス起動をモックし、上流の root 判定は実行します。

```bash
DOTFILES_NVIM_LSPCONFIG="/nix/store/<hash>-vimplugin-nvim-lspconfig-<version>" \
  nvim --headless -u NONE -i NONE -l tests/lua/nvim_lsp_integration_test.lua
DOTFILES_NVIM_LSPCONFIG="/nix/store/<hash>-vimplugin-nvim-lspconfig-<version>" \
  nvim --headless -u NONE -i NONE -l tests/lua/nvim_typescript_test.lua
```

```powershell
pwsh -NoProfile -File scripts/powershell/tests/Invoke-Tests.ps1 -Path scripts/powershell/tests/chezmoi/NvimShell.Tests.ps1 -MinimumCoverage 0
```

全 plugin の起動テストは `neovim-native` に含まれます。一時 XDG data に Home Manager の native package を配置し、生成された `init.lua` と Nix 管理の基本設定を読み込みます。旧設定の移行も、評価済み Home Manager の preflight、`checkLinkTargets`、`writeBoundary`、`linkGeneration` を一時 HOME で実行し、退避・dry-run・再実行・衝突時の無変更を検証します。ホストへの反映は不要です。

Windows の PowerShell 検証を macOS で通しても、Windows 実機での compiler、PATH、WSL transport、画像、IME、キーバインドを検証したことにはなりません。これらと Linux/Devcontainer の実機動作は対応環境で別途確認してください。
