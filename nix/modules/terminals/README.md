# Terminal modules

`alacritty/default.nix` は package と設定を直接宣言する Home Manager module です。
theme/size は `appearance.nix` の共通値を `programs.alacritty.settings` へ渡し、フォント・配色・Option/Alt の扱いを管理します。

- `nix/discover-modules.nix` が `default.nix` を自動検出し、統合・standalone Home Manager で同じ module を使います。`nix/defaults.nix` の `programs.alacritty.enable` で有効化し、個別の import パスや公開一覧は登録しません。
- Alacritty はタブ・ペインを持ちません。分割・タブ・ペイン移動は Herdr または各アプリの標準機能に任せ、terminal 固有の共通キー契約を増やしません。
- Shift+Enter は複数行入力のため改行を送ります。macOS は Option を Alt として ESC シーケンスを送り、フォントサイズは `Ctrl+Shift+0/+/-` に割り当てます。コピー・貼り付けは Alacritty の標準キーを使います。
- Alacritty の terminfo は本体と別出力です。module が `package.terminfo` をユーザープロファイルへ追加し、`TERM=alacritty` の子プロセスが terminfo を解決できるようにします。
- Windows Terminal は chezmoi が設定を配布し、PowerShell 7 を既定プロファイルにします。NixOS-WSL は自動生成される `NixOS` プロファイルから起動します。
- Windows のパッケージは `windows/winget/packages.json` が管理します。

`XDG_CONFIG_HOME` は Home Manager の `xdg.configHome` で指定してください。
