# Chezmoi ディレクトリ構造

Windows 用 source tree は WezTerm 設定とフォント導入で構成します。

| 編集元                                                                          | 内容・配置先                                                                              |
| ------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| `terminals/wezterm/wezterm.lua`                                                 | Windows WezTerm 設定。deploy script が `%USERPROFILE%/.config/wezterm/wezterm.lua` に配置 |
| `.chezmoiscripts/deploy/terminals/run_onchange_deploy.ps1.tmpl`                 | Windows の WezTerm 設定を配置                                                             |
| `.chezmoiscripts/deploy/terminals/run_onchange_install_udev_gothic_nf.ps1.tmpl` | Windows のユーザー領域に UDEV Gothic NF を導入                                            |
| `.chezmoi.toml.tmpl`, `.chezmoiignore.tmpl`                                     | source directory と Windows 適用対象を定義                                                |

PowerShell のインストールは WinGet manifest、WezTerm の NixOS-WSL 側設定は Home Manager が所有します。
