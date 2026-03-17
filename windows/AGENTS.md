# windows: Windows 側設定の編集基準

## 管理対象

- `winget/packages.json`: winget パッケージ
- `npm/packages.json`: npm グローバルパッケージ
- `pnpm/packages.json`: pnpm グローバルパッケージ
- `.wslconfig*`: WSL 設定
- `docker-vhd-size.conf`, `expand-docker-vhd.ps1`: Docker VHD 管理

## 編集ルール

- ターミナル設定は `windows/` ではなく `chezmoi/terminals/` を編集する。
- 実行ロジック変更は `scripts/powershell/` 側を編集する。

## 実行

```powershell
pwsh -File scripts/powershell/install.ps1
```
