# デスクトップキー設定の所有範囲

共通キー設定とユーザー設定は `nix/home/keybindings/`、OS service と有効化は `nix/hosts/<system>/<environment>/` が所有します。macOS は AeroSpace、native NixOS は Hyprland を使います。NixOS-WSL には compositor を導入しません。

Windows 用 GlazeWM の設定生成・配布機能は削除しました。Windows デスクトップのキー配列はこの repository では管理しません。WezTerm の pane、tab、launcher 操作は WezTerm 設定の責務です。

## WezTerm の境界

Windows の WezTerm 設定は chezmoi の `terminals/wezterm/wezterm.lua` に置きます。PowerShell を既定シェルとし、NixOS-WSL は別の launcher profile から起動します。Unix の設定は Home Manager が管理します。

Nix のテストは純粋な設定生成と実効値を検査します。実機の compositor 動作やキー入力は対象 host 上で確認します。
