# Terminal modules

`ghostty/default.nix` は、package と設定を直接宣言する Home Manager module です。
theme/size は各 `default.nix` の標準 `programs.*.settings` に定義します。Ghostty は共通キー配列も `programs.ghostty.settings.keybind` に集約し、WSL では Windows export の `ghostty.conf` を読み込みます。

- `nix/discover-modules.nix` が`default.nix` を自動検出し、統合・standalone Home Manager で同じ module を使います。`nix/defaults.nix` の `programs.ghostty.enable` で有効化し、個別の import パスや公開一覧は登録しません。
- Ghostty の Bash / zsh integration は Home Manager で有効化します。Unix の Bash 起動設定は `nix/modules/shells/bash/default.nix`、zsh の設定は `nix/modules/shells/zsh/default.nix` が管理します。両 module も自動検出し、標準の `programs.bash.enable` / `programs.zsh.enable` に従います。OSC 7 は各 terminal の公式 shell integration が送信します。
- Ghostty の `default.nix` が Linux の systemd / D-Bus 連携を有効化し、macOS の package に `pkgs.ghostty-bin` を指定します。Linux は Home Manager の既定 package を使います。
- WSL の Ghostty GUI は WSLg が必要です。
- Windows Terminal は chezmoi が設定を配布し、PowerShell 7 を既定プロファイルにします。NixOS-WSL は自動生成される `NixOS` プロファイルから起動します。
- Windows のパッケージは `windows/winget/packages.json` が管理します。

`XDG_CONFIG_HOME` は Home Manager の `xdg.configHome` で指定してください。
macOS の `~/Library/Application Support/com.mitchellh.ghostty/config` に別の設定がある場合は、その設定も Ghostty に読み込まれます。
