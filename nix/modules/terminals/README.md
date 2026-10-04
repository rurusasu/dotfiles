# Terminal modules

`ghostty/defaults.nix` と `wezterm/defaults.nix` は、package と設定を直接宣言する Home Manager module です。
theme/size は各 `defaults.nix` に直接定義します。WezTerm のフォントと追加設定は `wezterm/wezterm.lua` に直接書き、Home Manager の `extraConfig` で読み込みます。

- `nix/modules/{darwin,nixos,wsl}/default.nix` の `home-manager.sharedModules` から直接読み込みます。
- standalone Home Manager も同じ `defaults.nix` を読み込みます。
- 両 terminal の Bash / zsh integration は Home Manager で有効化します。Unix の Bash 起動設定は `nix/home/common.nix`、zsh は `nix/modules/shells/zsh/default.nix` が管理し、chezmoi の Unix adapter は上書きしません。
- Linux の Ghostty systemd / D-Bus 連携は `nix/modules/nixos/ghostty.nix` で有効化します。
- macOS の Ghostty package は `nix/modules/darwin/ghostty.nix` で指定し、Linux は Home Manager の既定 package を使います。
- Darwin の WezTerm terminfo と `TERMINFO_DIRS` は `nix/modules/darwin/wezterm.nix` が管理します。
- WSL の Ghostty GUI は WSLg が必要です。
- Windows の設定・launcher・shortcut は chezmoi 側を直接編集し、Windows のみ配布します。
- Windows の WezTerm winget ID は既存の package catalog、PATH/verifier は `wezterm/windows-install.nix` が管理します。

`checks.<system>.ghostty-config` は Lua 構文と Windows 専用の配布を検証します。

`XDG_CONFIG_HOME` は Home Manager の `xdg.configHome` で指定してください。
macOS の `~/Library/Application Support/com.mitchellh.ghostty/config` に別の設定がある場合は、その設定も Ghostty に読み込まれます。
