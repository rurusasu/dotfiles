# Chezmoi ディレクトリ構造

## 編集元と配置方法

`dot_*` の直接配置と、カテゴリ別ディレクトリからスクリプトで配置する方式を併用しています。すべての設定が deploy スクリプト経由というわけではありません。除外条件は `.chezmoiignore` と `.chezmoiignore.tmpl`、実行内容は `.chezmoiscripts/` を確認します。

| 編集元                                                    | 内容・配置方式                                           |
| --------------------------------------------------------- | -------------------------------------------------------- |
| `dot_config/nvim/`                                        | Neovim。`~/.config/nvim` へ直接配置                      |
| `dot_config/git/hooks/`                                   | Git hooks。直接配置                                      |
| `dot_gitconfig.tmpl`、`dot_gitconfig-work.tmpl`           | Git 設定テンプレート。直接配置                           |
| `dot_agents/`、`dot_codex/`、`dot_cursor/`、`dot_gemini/` | AI ツール設定。旧 `llms/` ではない                       |
| `shells/`                                                 | bash / zsh / PowerShell / profile。deploy adapter が配置 |
| `cli/`                                                    | fd、ripgrep、starship、ghq、zoxide など                  |
| `terminals/`                                              | WezTerm、Windows Terminal など                           |
| `editors/`                                                | VS Code、Cursor、Zed。Neovim は含まない                  |
| `github/`                                                 | GitHub テンプレートなど                                  |
| `ssh/`                                                    | SSH 設定テンプレート                                     |
| `.chezmoiscripts/deploy/`                                 | カテゴリ別、OS 別の配置処理                              |
| `.chezmoiscripts/run_onchange_install-*`                  | 宣言に基づくユーザーツール導入                           |

Windows も Neovim の編集元は `dot_config/nvim/` です。起動時の実際の配置先は `:lua print(vim.fn.stdpath("config"))` で確認できます。

## Neovim の内部構造

```text
dot_config/nvim/
├── init.lua                  # 最低版確認と起動順序
├── lua/config/               # options、keymaps、標準 LSP / 補完 / Tree-sitter
├── lua/plugins/              # lazy.nvim の plugin specs
├── after/lsp/                # 上流定義に重ねるサーバー別設定
└── treesitter.json           # Nix と非 Nix の共通パーサー一覧
```

パーサー／クエリの Nix 配布は `nix/packages/neovim/default.nix`、LSP のパッケージ配布は `nix/packages/sets.nix` にあります。運用・テストは [Neovim](./neovim.md) を参照してください。

## ファイル命名規則

| 属性          | 意味                                                                       |
| ------------- | -------------------------------------------------------------------------- |
| `dot_`        | `.` で始まる名前                                                           |
| `private_`    | グループ・その他のアクセス権を制限（ファイル／ディレクトリで権限が異なる） |
| `executable_` | 実行可能ファイル                                                           |
| `.tmpl`       | テンプレート展開                                                           |

`AGENTS.md` / `README.md` は配置対象に含めません。
