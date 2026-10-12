# Chezmoi ディレクトリ構造

Windows 用 source tree は WezTerm 設定だけで構成します。

| 編集元                                                          | 内容・配置先                                                                              |
| --------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| `terminals/wezterm/wezterm.lua`                                 | Windows WezTerm 設定。deploy script が `%USERPROFILE%/.config/wezterm/wezterm.lua` に配置 |
| `.chezmoiscripts/deploy/terminals/run_onchange_deploy.ps1.tmpl` | Windows の WezTerm 設定を配置                                                             |
| `.chezmoi.toml.tmpl`, `.chezmoiignore.tmpl`                     | source directory と Windows 適用対象を定義                                                |

PowerShell のインストールは WinGet manifest、WezTerm の NixOS-WSL 側設定は Home Manager が所有します。
