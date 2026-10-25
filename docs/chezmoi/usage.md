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
