# Chezmoi ディレクトリ構造

Windows 用 source tree は WezTerm 設定、PowerShell プロファイル、フォント導入で構成します。

| 編集元                                                                          | 内容・配置先                                                                  |
| ------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| `terminals/wezterm/wezterm.lua`                                                 | Windows WezTerm 設定の正本。native template が参照                            |
| `Documents/PowerShell/Microsoft.PowerShell_profile.ps1`                         | Windows の PowerShell 7 の WezTerm 補完と PSReadLine の履歴候補表示           |
| `dot_config/git/config`                                                         | Windows Git の相対 worktree リンク設定。Unix Git / gwq は Home Manager が管理 |
| `dot_config/wezterm/wezterm.lua.tmpl`                                           | `%USERPROFILE%/.config/wezterm/wezterm.lua` を chezmoi が直接管理             |
| `.chezmoiscripts/deploy/terminals/run_onchange_install_udev_gothic_nf.ps1.tmpl` | Windows のユーザー領域に UDEV Gothic NF を導入                                |
| `.chezmoi.toml.tmpl`, `.chezmoiignore.tmpl`                                     | source directory と Windows 適用対象を定義                                    |

PowerShell のインストールは WinGet manifest、WezTerm の NixOS-WSL 側設定は Home Manager が所有します。
