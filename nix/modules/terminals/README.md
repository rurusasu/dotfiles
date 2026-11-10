# Terminal modules

`ghostty/default.nix` は Ghostty の package・設定・キー割り当てを所有する Home Manager module です。macOS / Linux / WSL で同じ管理経路を使い、Windows の export から Ghostty 設定を読み込みません。

- 共通アプリ module は `nix/modules/default.nix` の `imports` に明示する。アプリ内の子 module は親の `imports`、OS 固有の module は各 hosts から読み込む。有効化は型付き option で選び、package・設定・service・activation を enable に従わせる。
- 標準キーをクリアし、コピー・貼り付け、フォント、検索・スクロール、設定、新規ウィンドウ、全画面のキーだけを定義します。分割・タブ・ペイン移動・サイズ変更・undo / redo のキーは割り当てません。
- ターミナル内のタブ・ペイン・セッションは `nix/modules/terminals/herdr/default.nix` が管理する Herdr の `Ctrl+Space` prefix で操作します。
- Ghostty の Bash / zsh integration は Home Manager で有効化します。シェル設定は `shells/bash/default.nix` と `shells/zsh/default.nix` が管理します。
- Linux の systemd / D-Bus 連携と macOS の `pkgs.ghostty-bin` 選択は Ghostty module が扱います。WSL の GUI には WSLg が必要です。
- Windows Terminal は chezmoi が設定を配布し、標準ショートカットと PowerShell 7 を使います。Windows の package は `chezmoi/winget/packages.json` が管理します。

`XDG_CONFIG_HOME` は Home Manager の `xdg.configHome` で指定してください。
macOS の `~/Library/Application Support/com.mitchellh.ghostty/config` に別の設定がある場合は、その設定も Ghostty に読み込まれます。
