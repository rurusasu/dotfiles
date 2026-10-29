# Chezmoi ディレクトリ構造

Windows 用 source tree は Windows Terminal 設定、PowerShell プロファイル、フォント導入で構成します。

| 編集元                                                                                           | 内容・配置先                                                                        |
| ------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------- |
| `AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/modify_settings.json` | Windows Terminal の既存 `settings.json` に管理キーをマージする modify-template      |
| `AppData/Local/Microsoft/Windows Terminal/Fragments/dotfiles/catppuccin-mocha.json`              | Windows Terminal に Catppuccin Mocha 配色を追加する fragment                        |
| `Documents/PowerShell/Microsoft.PowerShell_profile.ps1`                                          | Windows の PowerShell 7 の PSReadLine の履歴候補表示と共通エイリアス                |
| `dot_config/git/config`                                                                          | Windows Git の相対 worktree リンク設定。Unix Git / gwq は Home Manager が管理       |
| `.chezmoiscripts/deploy/terminals/run_onchange_install_udev_gothic_nf.ps1.tmpl`                  | Windows のユーザー領域に UDEV Gothic NF を導入                                      |
| `.chezmoiscripts/deploy/terminals/run_onchange_set_windows_terminal.ps1.tmpl`                    | `HKCU:\Console\%%Startup` を設定し、Windows Terminal 安定版を既定のターミナルにする |
| `.chezmoi.toml.tmpl`, `.chezmoiignore.tmpl`                                                      | source directory と Windows 適用対象を定義                                          |

PowerShell 7 と Windows Terminal のインストールは WinGet manifest が所有します。Unix の WezTerm / Ghostty 設定は Home Manager が所有します。
