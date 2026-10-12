# windows: Windows 側設定の編集基準

## 管理対象

- `winget/packages.json`: Windows にインストールする WinGet / Microsoft Store パッケージと installer metadata の SSOT
- `npm/packages.json`: Windows の npm グローバルパッケージの SSOT
- `pnpm/packages.json`: Windows の pnpm グローバルパッケージの SSOT
- `.wslconfig*`: WSL 設定
- `docker-vhd-size.conf`, `expand-docker-vhd.ps1`: Docker VHD 管理

## 編集ルール

- ターミナル設定は `windows/` ではなく `chezmoi/terminals/` を編集する。
- 実行ロジック変更は `scripts/powershell/` 側を編集する。
- パッケージ追加・削除と検証コマンドなどの metadata は各 `packages.json` を直接編集する。Nix からは生成しない。
- Unix のパッケージ・設定は `nix/modules/` が管理する。Windows manifest との共通 catalog は置かない。

## 実行

```powershell
pwsh -File scripts/powershell/install.ps1
```
