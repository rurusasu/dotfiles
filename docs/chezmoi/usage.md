# Chezmoi の使い方

## Windows での初回適用

リポジトリのルートで実行します。chezmoi 自体は Windows installer が WinGet で導入します。

```powershell
chezmoi init --source "$PWD/chezmoi"
task chezmoi
```

`task chezmoi` は Windows の WezTerm 設定と PowerShell プロファイルを適用します。NixOS-WSL では実行しません。

## 更新

```powershell
task chezmoi
```

差分を確認する場合:

```powershell
chezmoi --source "$PWD/chezmoi" diff
```

## 配置先とプロファイル

chezmoi は `%USERPROFILE%/.config/wezterm/wezterm.lua` と `%USERPROFILE%/Documents/PowerShell/Microsoft.PowerShell_profile.ps1` を管理します。Windows WezTerm は PowerShell を既定シェルとして起動します。NixOS-WSL は別の `NixOS (WSL)` launcher profile から起動します。

PowerShell 7 は、対話コンソールで PSReadLine が `PredictionViewStyle` オプションを提供している場合、`ListView` で履歴の候補を入力中に表示し、文字を追加すると候補を絞り込みます。未実行のコマンドやサブコマンドは通常の Tab 補完で選びます。WSL の有無に依存しません。適用後は PowerShell の新しいタブを開くか、`. $PROFILE` で再読み込みします。

macOS、Linux、NixOS-WSL 内部の WezTerm 設定は Home Manager が管理し、Windows 用 chezmoi source からは配布しません。

## Windows の共通エイリアス

Windows のエイリアスと関数も chezmoi の PowerShell profile が管理します。WSL の Zsh と同じ名前・オプションで Windows の実行ファイルを呼び出します。

| コマンド                    | Windows 側の動作                                  |
| --------------------------- | ------------------------------------------------- |
| `eza`                       | アイコン・自動色・tree 表示                       |
| `ls`                        | 深さ 1 の eza 表示                                |
| `ll` / `la` / `lt` / `lla`  | Zsh と同じ eza の表示オプション                   |
| `grep` / `find`             | `rg.exe` / `fd.exe`                               |
| `lg`                        | `lazygit.exe`                                     |
| `k` / `kgn` / `kgp` / `kgs` | kubectl と nodes / 全 namespace の pods・services |
| `kctx` / `kns`              | `kubectx.exe` / `kubens.exe`                      |
| `dotf`                      | chezmoi source の親のリポジトリで Task を実行     |

`eza`・`fd`・`ripgrep`・`lazygit` の導入情報は `windows/winget/packages.json` が管理します。`install.cmd -UserPhaseOnly` で導入し、`task chezmoi` と `. $PROFILE` で profile を反映します。Kubernetes の短縮コマンドは WSL と同様、対応する CLI を別途導入した環境で使えます。`nrs` / `nrt` / `nrb` は NixOS 固有なので Windows profile には定義しません。
