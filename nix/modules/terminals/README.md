# Terminal modules

`ghostty/defaults.nix` と `wezterm/defaults.nix` は、package と設定を直接宣言する Home Manager module です。
theme/size は各 `defaults.nix` に直接定義します。WezTerm のフォントと追加設定は `wezterm/wezterm.lua` に直接書き、Home Manager の `extraConfig` で読み込みます。

- `nix/hosts/` の各 OS 構成の `home-manager.sharedModules` から直接読み込みます。
- standalone Home Manager も同じ `defaults.nix` を読み込みます。
- 両 terminal の Bash / zsh integration は Home Manager で有効化します。Unix の Bash 起動設定は `nix/home/common.nix`、zsh のユーザー設定は `nix/home/shells/zsh/default.nix` が管理します。
- Linux の Ghostty systemd / D-Bus 連携は `nix/hosts/shared/linux-ghostty.nix` で有効化します。
- macOS の Ghostty package は `nix/hosts/aarch64-darwin/ghostty.nix` で指定し、Linux は Home Manager の既定 package を使います。
- Darwin の WezTerm terminfo と `TERMINFO_DIRS` は `nix/hosts/aarch64-darwin/wezterm.nix` が管理します。
- WSL の Ghostty GUI は WSLg が必要です。
- WezTerm の Bash / Zsh 連携は `TERM_PROGRAM=WezTerm` のときだけ読み込みます。Ghostty で同時に有効にすると、プロンプト連携が重複し、Zsh では空の `HOSTNAME` により Ghostty が受け付けない OSC 7 が送られることがあります。
- Windows は chezmoi が WezTerm 設定のみを配布し、PowerShell を既定シェルに設定します。NixOS-WSL は別の launcher profile として起動します。
- Windows の WezTerm winget ID は既存の package catalog、PATH/verifier は `wezterm/windows-install.nix` が管理します。

`checks.<system>.wezterm-config` は Lua 構文、PowerShell の既定設定、NixOS-WSL launcher profile を検証します。

`XDG_CONFIG_HOME` は Home Manager の `xdg.configHome` で指定してください。
macOS の `~/Library/Application Support/com.mitchellh.ghostty/config` に別の設定がある場合は、その設定も Ghostty に読み込まれます。
