# Cursor の LSP 設定

LSP・整形ツールの導入は `nix/modules/lsp.nix` の `home.packages`、Cursor の LSP 設定は `nix/modules/cursor/lsp.nix` が正本です。Neovim の内部 PATH は使いません。

`nix/modules/darwin/default.nix` と `nix/modules/nixos/default.nix` は、Home Manager の共通 module として両者を読み込みます。standalone Home Manager と System Manager も同じ定義を読み込みます。

Cursor の GUI 本体は既存の導入方法を維持し、Home Manager の `programs.cursor` は `package = null` で設定だけを管理します。`mutableUserSettings = true` により、未知の手動設定を保持しながら宣言した値を反映します。テーマ・フォントなどの基礎設定は、LSP キーを除去した既存 JSON と共通 `appearance.json` から取得します。

キー設定も `programs.cursor.profiles.default.keybindings` で既存の `chezmoi/editors/cursor/keybindings.json` をそのまま配布し、画面分割や移動などの操作を維持します。

## 配布先と Windows の境界

- macOS: `~/Library/Application Support/Cursor/User/settings.json`
- Linux: `~/.config/Cursor/User/settings.json`
- WSL Remote: `~/.cursor-server/data/Machine/settings.json`

WSL の Remote 設定はローカル User 設定とは別です。[Cursor サポートの説明](https://forum.cursor.com/t/typescript-language-features-broken-in-cursor-when-connected-to-a-coder-vm-ssh/159923/11)にある Machine 設定へ共通の LSP 設定を反映します。既存の非 LSP キーと JSON5 コメント付き入力を扱い、読み取り・解析に失敗したファイルは上書きしません。Windows の Cursor で WSL のプロジェクトを開く場合、言語拡張も WSL 側で有効にしてください。

chezmoi は Linux／macOS の Cursor 設定を書き込みません。Windows 本体の非 LSP 設定とキー配列の配布は従来どおり chezmoi が担当します。Windows 本体への言語サーバー導入と LSP 設定配布は行いません。

## 検証

`nix build .#checks.aarch64-darwin.nix-unit .#checks.aarch64-darwin.neovim-native --no-link --no-write-lock-file` で実効設定と Remote 設定のマージを検証します。後者は一時 HOME を使うため、利用者の Cursor 設定は変更しません。Cursor GUI と Windows→WSL の接続は実機確認の対象です。
