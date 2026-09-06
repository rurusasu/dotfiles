# Neovim の設定・導入・検証

## 要件と責務

最低 Neovim **0.12**。更新時は `nvim --version` と `:checkhealth vim.lsp` を確認します。動作確認済み版と採否の根拠は [最新化調査](./neovim-modernization-audit.md) に記録します。

- 設定の正本: `chezmoi/dot_config/nvim/`
- パッケージ/provider の正本: `nix/packages/sets.nix`
- Nix の Neovim wrapper: `nix/packages/neovim/default.nix`
- 言語別設定差分: `after/lsp/*.lua`
- パーサーの言語一覧: `treesitter.json`

設定は chezmoi が直接配置します。存在しない `chezmoi/editors/nvim` は編集しません。Windows も `%USERPROFILE%/.config/nvim` を共有し、PowerShell の `XDG_CONFIG_HOME` または `%LOCALAPPDATA%/nvim` junction を使います。実際の参照先は `:lua print(vim.fn.stdpath("config"))` で確認してください。

## Tree-sitter は何が必要か

構文解析とハイライトの実行は Neovim 本体の `vim.treesitter.start()` で行います。したがって、それだけのために nvim-treesitter の Lua プラグインをロードする必要はありません。ただし **言語ごとのパーサーバイナリと対応クエリ** は必要です。Neovim 同梱の少数言語だけでは Python、Nix、TSX などをカバーできません。[Neovim 公式](https://neovim.io/doc/user/treesitter/)

| 環境                            | 導入・更新                                                              | エディタ内の実行                                                              |
| ------------------------------- | ----------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| Nix (macOS / Linux / WSL)       | lock で固定した nixpkgs から対応する parser/query データを同梱          | wrapper の `DOTFILES_NVIM_TREESITTER` を runtimepath に追加。installer は無効 |
| Windows / 非 Nix / Devcontainer | nvim-treesitter `main` を導入専用に使用。不足データを非同期インストール | 標準 highlighter。旧 `nvim-treesitter.configs.setup` は使わない               |

Nix は継承先のクエリ（ecma、jsx、html_tags など）も閉包に含めます。「プラグインコードをロードしない」と「Nix store に nvim-treesitter 由来のパッケージが一切存在しない」は別です。ファイルタイプ `sh` / `javascriptreact` / `typescriptreact` は対応する grammar に明示登録します。

非 Nix のビルドには **tree-sitter CLI >= 0.26.1、C コンパイラ、curl、tar** が必要です。CLI は npm 版ではなく OS の package manager を使います。Windows の CLI は `tree-sitter.tree-sitter-cli` を catalog に登録済みです。MSVC 利用時は既存の `nvim-msvc` 関数／Developer PowerShell など、コンパイラに PATH が通る環境で起動します。[installer の要件](https://github.com/nvim-treesitter/nvim-treesitter)

導入の失敗は `:messages` を確認し、環境を直して再起動してください。parser だけ残った不完全な導入は query と合わせて再導入します。非 Nix のデータ更新は `:TSUpdate`、Nix は lock/package の更新と OS に合う Nix activation を使います。環境変数だけを偽装して installer を無効にしないでください。

インデントは標準 filetype indent / smartindent を使います。旧 nvim-treesitter の `indent = { enable = true }` と完全に同一の動作ではありません。パーサー未導入時は従来 syntax にフォールバックしますが、ABI 不一致や壊れた query は隠しません。

## LSP

nvim-lspconfig は上流のサーバー定義を供給し、起動は `vim.lsp.config` / `vim.lsp.enable`、共通処理は `LspAttach` で行います。Mason やその PATH 補正は不要です。独自の言語別設定は `after/lsp/` に置き、上流の定義を複製しません。

| 対象                   | サーバー／実行ファイル     | 補足                                                            |
| ---------------------- | -------------------------- | --------------------------------------------------------------- |
| Nix                    | nixd                       | Windows は node + wsl.exe + nix-lsp-wsl-proxy.mjs + WSL 内 nixd |
| Go                     | gopls                      | Windows 自動 provider は未提供。未導入ならスキップ              |
| Rust                   | rust-analyzer              | clippy、保存時整形                                              |
| JS / TS                | tsc (TS7+) / ts_ls (TS5/6) | ネイティブ版優先、旧版の互換経路を維持                          |
| JS / TS lint           | oxlint                     | 上流の project-local cmd、設定ファイル検出、Astro 対応を維持    |
| YAML                   | yaml-language-server       | Nix / pnpm                                                      |
| TOML                   | taplo                      | Nix / winget                                                    |
| Shell                  | bash-language-server       | Nix / pnpm                                                      |
| Lua                    | lua-language-server        | LuaJIT / vim globals                                            |
| Markdown               | marksman                   | Nix / winget                                                    |
| Python lint/format     | ruff                       | hover は ty に任せる                                            |
| Python type/completion | ty                         | ty.toml / pyproject.toml などを root とする                     |

TypeScript 7 の `tsc --lsp --stdio` を優先し、使用できない環境では typescript-language-server へフォールバックします。両方を同じバッファへ起動しません。旧サーバーには TS5/6 の `tsserver.js` が必要です。global TypeScript を7に更新しただけでは旧サーバーの依存は満たせません。必要な旧プロジェクトには対応する TS5/6 を project-local に保持してください。TS 用の上流設定は Deno 判定も行います。

未導入 executable は起動対象から外し、後から別の project-local executable があるプロジェクトを開くケースも再評価します。実行ファイルが存在しても server 初期化やプロジェクト設定の成功までは保証しません。`:checkhealth vim.lsp`、`:messages`、`:lua vim.print(vim.lsp.get_clients({bufnr=0}))` を確認します。

選択順は project-local tsc → PATH tsc → project-local tsgo → PATH tsgo → local/PATH の従来サーバーです。バージョン確認は候補ごとに最大3秒。成功した選択は root ごとにセッション中固定し、不在はキャッシュしません。特定の旧機能のため従来サーバーを明示指定する場合は、LSP 起動前に `vim.g.dotfiles_typescript_server = "ts_ls"` を設定します。`"tsc"` を指定すると native のみに限定します。選択変更・依存更新後は再起動してください。

旧 nvim-lspconfig cache に tsc 定義がなくても、TS の filetypes を引き継いで無関係な言語へ起動しないようにしています。現行上流が持つ settings/commands は保持します。plugin 更新は `:Lazy update nvim-lspconfig`、起動・配布の互換テストは現行 checkout と Nix 固定2.11.0の両方を使います。

### TS7 終了時の未解決警告

2026-09-06 の tsc 7.0.2 / Neovim 0.12.5 では、正常な shutdown 要求後にも `context canceled` と exit code 1 を観測しました。dotfiles をロードせず、上流 tsc 設定だけを有効化した隔離プローブでも再現しています。接続・補完は成功していますが、終了コードまで正常とはしていません。通知を隠す workaround は追加せず、必要なら上記の `ts_ls` 明示選択と TS5/6 を使ってください。[Microsoft の過去の類似ログ](https://github.com/microsoft/typescript-go/issues/3026) は参考であり、同一原因や現在の修正予定を証明するものではありません。

Python は Ruff、Rust は rust-analyzer だけで保存時整形します（同期、上限3秒）。手動 `Space f` も同じ優先指定を使い、Python で Ruff/ty の二重整形を避けます。

Nix の options 補完には既存の個人設定として `~/.dotfiles` の `nixosConfigurations.nixos.options` を参照しています。別 host/output を補完したい場合は `after/lsp/nixd.lua` の式を変更してください。Nix フォーマットには nixfmt が別途必要です。

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

Snacks は端末の画像対応を自動判定します。PDF は既存の Poppler 経路を保持し、外部プロセスは `vim.system` で終了コード・10秒上限を確認します。ただし変換待ちは同期なので、大きな PDF の UI 停止を完全には解消していません。

Windows のカスタム floating terminal、Oil のドライブ一覧互換処理は維持します。0.12 更新だけを理由に、実機での根拠なく既存 workaround を撤去しません。

## 検証

リポジトリのルートから実行します。作業ツリーの未追跡ファイルを含めて検証する場合は `path:.`、コミット済み checkout は通常の `.` を使えます。

```bash
nix build path:.#checks.aarch64-darwin.neovim-native --no-link
# Linux x86_64: checks.x86_64-linux.neovim-native
nix build path:.#checks.aarch64-darwin.package-provider-coverage --no-link
nix build path:.#winget-export --no-link --print-out-paths
nvim --headless -u NONE -i NONE -l tests/lua/nvim_modern_test.lua
nvim --headless -u NONE -i NONE -l tests/lua/nvim_treesitter_installer_test.lua
bats tests/bash/bootstrap_entrypoint.bats
```

実 LSP テストには ty、ruff、TS7 の tsc と新しい nvim-lspconfig checkout が必要です。例のパスは実際の配置に合わせます。テストは一時バッファを使い、プロジェクトファイルを保存しません。

旧版の実 LSP テストでは TS5/6 と対応する typescript-language-server を PATH の先頭に置き、`DOTFILES_NVIM_TS_SERVER=ts_ls` を指定します（この環境変数はテストの期待値指定で、実設定の選択は上記の Lua global）。TS5.9.3＋従来サーバー5.3.0でも初期化・補完応答まで確認しました。routing テストはプロセス起動をモックし、上流の root 判定は実行します。

```bash
DOTFILES_NVIM_LSPCONFIG="$HOME/.local/share/nvim/lazy/nvim-lspconfig" \
  nvim --headless -u NONE -i NONE -l tests/lua/nvim_lsp_integration_test.lua
DOTFILES_NVIM_LSPCONFIG="$HOME/.local/share/nvim/lazy/nvim-lspconfig" \
  nvim --headless -u NONE -i NONE -l tests/lua/nvim_typescript_test.lua
```

```powershell
pwsh -NoProfile -File scripts/powershell/tests/Invoke-Tests.ps1 -Path scripts/powershell/tests/chezmoi/NvimShell.Tests.ps1 -MinimumCoverage 0
```

全 plugin の起動テストでは、一時 XDG config にこのソースを `nvim/` として配置し、一時 data に既存の lazy plugin checkout を参照させます。`-u path/to/init.lua` と runtimepath の手動追加だけでは、lazy.nvim の runtimepath リセット後に設定が失われるため通常配置を再現しません。ホストに `chezmoi apply` する必要はありません。

Windows の PowerShell 検証を macOS で通しても、Windows 実機での compiler、PATH、WSL transport、画像、IME、キーバインドを検証したことにはなりません。これらと Linux/Devcontainer の実機動作は対応環境で別途確認してください。
