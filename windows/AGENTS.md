# windows: Windows 側設定の編集基準

## 管理対象

- `winget/packages.json`: Windows にインストールする WinGet 標準 import 形式の WinGet / Microsoft Store パッケージの正本
- `.wslconfig*`: WSL 設定

## 編集ルール

- Windows WezTerm 設定は `chezmoi/terminals/wezterm/` を編集する。
- 実行ロジック変更は `scripts/powershell/` 側を編集する。
- パッケージ追加・削除と標準 source / Scope は `winget/packages.json` を直接編集する。Nix からは生成しない。
- Unix のパッケージ・設定は `nix/modules/` が管理する。Windows manifest との共通 catalog は置かない。

## 実行

```powershell
pwsh -File scripts/powershell/install.ps1
```
