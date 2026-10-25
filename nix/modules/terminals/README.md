# Terminal modules

`ghostty/default.nix` と `wezterm/default.nix` は、package と設定を直接宣言する Home Manager module です。
theme/size は各 `default.nix` の標準 `programs.*.settings` に定義します。Ghostty は共通キー配列も `programs.ghostty.settings.keybind` に集約し、WSL では Windows export の `ghostty.conf` を読み込みます。WezTerm のフォントは `programs.wezterm.settings.font`、追加の動作・キー設定は `wezterm/wezterm.lua` の `extraConfig` で管理します。

- `nix/default.nix:homeModules.common` が両方の `default.nix` を一度だけ読み込み、統合・standalone Home Manager で共有します。
- Ghostty の Bash / zsh integration は Home Manager で有効化します。Unix の Bash 起動設定は `nix/modules/shells/bash/default.nix`、zsh の設定は `nix/modules/shells/zsh/default.nix` が管理します。両 module は `nix/default.nix:homeModules.common` から読み込みます。OSC 7 は各 terminal の公式 shell integration が送信します。
- Ghostty の `default.nix` が Linux の systemd / D-Bus 連携を有効化し、macOS の package に `pkgs.ghostty-bin` を指定します。Linux は Home Manager の既定 package を使います。
- Darwin の WezTerm は `programs.wezterm.package.terminfo` の store path を Lua に渡し、起動する shell の `TERMINFO_DIRS` に設定します。
- WSL の Ghostty GUI は WSLg が必要です。
- WezTerm の Bash / Zsh 連携は `TERM_PROGRAM=WezTerm` のときだけ読み込みます。Ghostty で同時に有効にすると、プロンプト連携が重複し、Zsh では空の `HOSTNAME` により Ghostty が受け付けない OSC 7 が送られることがあります。
- Windows は chezmoi が WezTerm 設定のみを配布し、PowerShell を既定シェルに設定します。NixOS-WSL は別の launcher profile として起動します。
- Windows の WezTerm winget ID・PATH・verifier は `windows/winget/packages.json` が管理します。

`checks.<system>.wezterm-config` は Lua 構文、PowerShell の既定設定、NixOS-WSL launcher profile を検証します。

`XDG_CONFIG_HOME` は Home Manager の `xdg.configHome` で指定してください。
macOS の `~/Library/Application Support/com.mitchellh.ghostty/config` に別の設定がある場合は、その設定も Ghostty に読み込まれます。
