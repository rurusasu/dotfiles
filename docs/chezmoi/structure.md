# Chezmoi ディレクトリ構造

## 編集元と配置方法

`dot_*` の直接配置と、カテゴリ別ディレクトリからスクリプトで配置する方式を併用しています。すべての設定が deploy スクリプト経由というわけではありません。除外条件は `.chezmoiignore` と `.chezmoiignore.tmpl`、実行内容は `.chezmoiscripts/` を確認します。

| 編集元                                          | 内容・配置方式                                           |
| ----------------------------------------------- | -------------------------------------------------------- |
| `dot_config/git/hooks/`                         | Git hooks。直接配置                                      |
| `dot_gitconfig.tmpl`、`dot_gitconfig-work.tmpl` | Git 設定テンプレート。直接配置                           |
| `dot_agents/`、`dot_codex/`、`dot_gemini/`      | AI ツール設定。旧 `llms/` ではない                       |
| `shells/`                                       | bash / zsh / PowerShell / profile。deploy adapter が配置 |
| `cli/`                                          | fd、ripgrep、starship、ghq、zoxide など                  |
| `terminals/`                                    | WezTerm、Windows Terminal など                           |
| `github/`                                       | GitHub テンプレートなど                                  |
| `ssh/`                                          | SSH 設定テンプレート                                     |
| `.chezmoiscripts/deploy/`                       | カテゴリ別、OS 別の配置処理                              |
| `.chezmoiscripts/run_onchange_install-*`        | 宣言に基づくユーザーツール導入                           |

Neovim は chezmoi の配布対象ではなく、Home Manager が管理します。

## Neovim の内部構造

```text
nix/modules/nvim/
├── default.nix               # Home Manager の設定・Lua の配置
├── plugins.nix               # プラグインの導入・設定の呼び出し
├── init.lua                  # エディタの基本設定・補助機能の読み込み
└── lua/
    ├── config/               # keymaps、共通 LSP・整形 / 補完 / Tree-sitter
    └── plugins/              # プラグインごとの Lua 設定
```

起動設定は `nix/modules/nvim/default.nix`、プラグインの導入と設定の呼び出しは `nix/modules/nvim/plugins.nix`、Lua 設定の本体は `nix/modules/nvim/lua/plugins/` にあります。Home Manager が `init.lua` を生成します。LSP サーバーの package/provider 定義は `nix/packages/catalog/lsp.nix`、`sets.nix` は公開入口です。運用・テストは [Neovim](./neovim.md) を参照してください。

## ファイル命名規則

| 属性          | 意味                                                                       |
| ------------- | -------------------------------------------------------------------------- |
| `dot_`        | `.` で始まる名前                                                           |
| `private_`    | グループ・その他のアクセス権を制限（ファイル／ディレクトリで権限が異なる） |
| `executable_` | 実行可能ファイル                                                           |
| `.tmpl`       | テンプレート展開                                                           |

`AGENTS.md` / `README.md` は配置対象に含めません。
