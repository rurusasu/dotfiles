# Neovim 最新化調査

調査日: 2026-09-06。対象は [issue #182](https://github.com/rurusasu/dotfiles/issues/182)、`chezmoi/dot_config/nvim` 全体、およびその package/deploy/test/documentation 経路。無関係なシェル・サービス全体の最新化は対象外です。

## バージョンを混同しない

ローカル実行は Neovim 0.12.5、TypeScript 7.0.2、typescript-language-server 6.0.0。root flake の nixpkgs は `c043004d1c6985732bcc1cbc5a9c9aecbbb4e0f0`、Neovim 0.12.5、tree-sitter 0.26.11。一方、その Nix TypeScript は5.9.3であり、ユーザーの global pnpm と同じ版ではありません。

安定版の判断は [Neovim 0.12.5 release](https://github.com/neovim/neovim/releases/tag/v0.12.5) と [0.12 の変更点](https://neovim.io/doc/user/news-0.12/) を基準にします。Web の一般的な news/API ページが開発版0.13を示す場合、その記述だけで0.12に未実装の API を導入しません。

## 調査結果と採否

| 領域             | 確認した問題／比較                                                              | 今回の対応                                                                        |
| ---------------- | ------------------------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| LSP API          | 旧 `require("lspconfig").…setup` と標準 config/enable の差                      | 標準 API、`after/lsp/`、共通 LspAttach に統一                                     |
| Mason            | issue の削除対象と実コードに差。plugin は既に不在だが固定 Python313 PATH が残存 | 残骸を削除。Nix / winget / pnpm に導入責務を集約                                  |
| LSP 数           | issue は10とするが実構成は12枠                                                  | 実構成を保持し、TS native/legacy を選択                                           |
| 補完             | cmp の依存群 vs 標準 vs blink.cmp                                               | 標準 completion/snippet 採用。候補 source の UX 差を明記                          |
| コメント         | Comment.nvim と標準 gc/gcc                                                      | 標準に統一                                                                        |
| Tree-sitter      | 本体 API と parser 配布を同一視すると多数言語を失う                             | Nix は対応 parser/query データ、非 Nix は導入専用 main                            |
| parser 互換性    | バイナリだけ存在しても継承 query / injection が欠ける可能性                     | Nix 依存閉包、22言語 query compile、実 capture / Markdown Python injection テスト |
| installer        | 旧 configs module は installed main で存在しない。async false と例外は異なる    | 現行 setup/install/await、部分導入の修復、失敗通知                                |
| インデント       | 標準 highlighter は旧 plugin indent の代替ではない                              | 標準 filetype indent に変更し、同等ではないと明示                                 |
| TS7              | tsc/tsgo native と旧 tsserver の配布条件が異なる                                | TS7優先、旧版フォールバック。Deno と二重 attach に注意                            |
| executable 判定  | 起動時一度だけの判定では後から開いた project-local server を見逃す              | ファイル切替時にも再評価                                                          |
| Python           | Ruff と ty が hover/format を競合する可能性                                     | hover は ty、保存整形は Ruff、動的 capability 登録後も検証                        |
| Oxlint           | 固定 cmd/filetypes は上流の local resolution、Astro を失う                      | 上流定義を利用                                                                    |
| Bash             | workspace glob の再帰指定が広すぎる                                             | 現行の拡張子 glob に限定                                                          |
| 診断表示         | 描画ごとに severity 別の診断全件を取得                                          | `vim.diagnostic.count` で件数取得                                                 |
| 外部プロセス     | Shell error / OS-open fallback / JSON Vimscript API                             | `vim.system`、`vim.ui.open`、`vim.json`、`vim.uv`                                 |
| UI 終了処理      | stdout への escape は headless にも漏れる                                       | UI 接続を確認して `nvim_ui_send`                                                  |
| lazy bootstrap   | clone 失敗後のキー待ちで headless が止まりうる                                  | timeout と error。対話待ちを撤去                                                  |
| 画像             | `force=true` と PDF 変換終了コード未検査                                        | 端末判定、変換失敗・timeout 検査。既存 Poppler 経路は維持                         |
| Windows provider | Bash/YAML/Marksman/CLI の自動導入不足                                           | pnpm/winget catalog と生成 manifest を追加                                        |
| Devcontainer     | 最低0.9判定、tmux の起動だけで Neovim 成功と表示                                | 最低0.12、子プロセス終了コード検査                                                |
| 文書             | 旧配置、存在しない導入コマンド、旧 AI キー、誤ったパッケージ schema             | 運用・構造・キー・package docs と AGENTS を同期                                   |

nvim-lspconfig 自体や `on_attach` が廃止されたという結論にはしません。廃止対象の旧 framework と、上流の設定データ・有効な callback を区別します。この dotfiles では共通処理を LspAttach に置く設計を選んでいます。[nvim-lspconfig 公式](https://github.com/neovim/nvim-lspconfig)、[標準 LSP API](https://neovim.io/doc/user/lsp/)

## 上流資料から判断した要点

- TS native はプロジェクトと PATH の TS7対応候補を調べ、Deno を除外します。既存 Nix の TS5.9を切り捨てないため互換経路が必要です。[tsc 定義](https://github.com/neovim/nvim-lspconfig/blob/master/lsp/tsc.lua)
- TypeScript の Go 実装が本流へ移ったことと、旧 typescript-language-server に必要な tsserver.js が存在することは別問題です。[Microsoft typescript-go](https://github.com/microsoft/typescript-go)、[TS7 RC の移行説明](https://devblogs.microsoft.com/typescript/announcing-typescript-7-0-rc/)
- 新 nvim-treesitter は旧 master の drop-in replacement ではなく、Neovim 本体に highlighter があっても compiler/CLI と parser/query の導入条件は残ります。[nvim-treesitter README](https://github.com/nvim-treesitter/nvim-treesitter)
- Python は Ruff の hover を止めて型サーバーに任せる上流例と整合させます。[Ruff editor setup](https://docs.astral.sh/ruff/editors/setup/)、[ty editors](https://docs.astral.sh/ty/editors/)
- Go / Rust の設定は現行の公開設定項目と照合し、変更理由のない静的解析・整形設定は維持します。[gopls settings](https://go.dev/gopls/settings)、[rust-analyzer configuration](https://rust-analyzer.github.io/book/configuration.html)
- Windows の ID は manifest を確認しました。[Tree-sitter CLI](https://github.com/microsoft/winget-pkgs/tree/master/manifests/t/tree-sitter/tree-sitter-cli)、[Marksman](https://github.com/microsoft/winget-pkgs/tree/master/manifests/a/Artempyanykh/Marksman)

## 今回置き換えないもの

Catppuccin、Oil、Gitsigns、Modes、which-key、autopairs、surround、indent-blankline、better-escape、tmux navigator、devcontainer-cli/ToggleTerm、Incline/devicons、Snacks、Sidekick は、標準 LSP/completion の導入だけでは同等に代替されません。既存の表示・navigation・container/AI workflow を維持します。残すことは全機能・全OSで無欠陥という意味ではありません。

`vim.pack` への全面変更は lazy.nvim の event/keys/dependency/UI 管理まで別の移行になるため採用しません。blink.cmp も有力ですが、今回の標準 API 優先方針では新しい補完エンジン依存を追加しません。[Neovim Lua API](https://neovim.io/doc/user/lua/)、[blink.cmp](https://github.com/saghen/blink.cmp)

Windows の Oil / float workaround、個人用 nixd option expression は維持し、その前提を運用文書に記載します。PDF の完全非同期化や全言語の formatting provider 統一は追加の UX 設計が必要です。

## 反証レビューと検証範囲

独立レビューで「本体更新で全 parser が不要」「TS7 の global 実行だけ確認すれば旧環境も安全」「installer の await で例外がなければ成功」という仮説を棄却しました。実際に `.sh/.jsx/.tsx` の言語登録、TS5/6互換、project-local の再検出、installer の false 戻り値を修正対象にしました。

ローカルでは data-only runtime の22言語、実 highlighter/query/injection、native 設定、installer の失敗/修復、Ruff/ty attach・保存整形、TS7 attach・補完応答を検証します。Nix の `neovim-native` check を継続実行可能にし、既存 bootstrap/Pester テストも更新します。具体的なコマンドと限界は [運用・検証](./neovim.md) を参照してください。

Windows 実機、Linux/Devcontainer の実稼働、terminal/IME/image の描画、ホストへの設定適用、GitHub hosted CI はこの macOS のローカル検証だけでは証明できません。起動時間の改善率も比較計測していないため主張しません。

### 実行結果

- Nix `neovim-native` / `package-provider-coverage`: 成功。22言語の parser/query と injection、補完キー分岐、installer の成功・失敗・部分修復、TS routing 28ケースを含む。
- TS routing: 最新 nvim-lspconfig と Nix 固定2.11.0の両方で成功。未導入 YAML の抑止と後続 local 導入も検証。
- 実 LSP: ty/Ruff の attach・整形、TS7.0.2の native attach・補完、TS5.9.3＋typescript-language-server 5.3.0の fallback attach・補完が成功。
- plugin 全体の隔離起動、および macOS 上での隔離 tmux 内起動が成功。cmp / nvim-treesitter installer をロードしないことを確認。
- bootstrap の Bats 3件、Windows shell / nixd proxy の Pester 4件が成功。生成 Windows manifest は export と一致。
- TS7終了時は **exit code 1 の警告が残る**。上流設定のみでも再現することまで切り分けた。実 LSP テストの成功は attach/format/completion とプロセス終了の確認を指し、TS7 の終了コード0を保証しない。詳細と回避選択は [運用文書](./neovim.md#ts7-終了時の未解決警告) を参照。
