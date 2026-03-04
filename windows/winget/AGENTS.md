# windows/winget: パッケージ管理運用

## 編集対象

- `packages.json` のみを source of truth とする。

## 実行コマンド

```powershell
winget export -o packages.json
winget import -i packages.json --accept-package-agreements
```

## 実装上の注意

- 一部パッケージは対話や手動操作が必要。
- 自動処理は `scripts/powershell/handlers/Handler.Winget.ps1` が担う。
