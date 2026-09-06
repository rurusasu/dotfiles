# windows/winget: パッケージ管理運用

## 編集対象

- SSOT は `nix/packages/sets.nix`。`packages.json` は `winget-export` の生成物。
- 生成・反映方法は `docs/nix/package-management.md` を参照する。

## 実行コマンド

```powershell
.\install.cmd
```

## 実装上の注意

- 一部パッケージは対話や手動操作が必要。
- 自動処理は `scripts/powershell/handlers/Handler.Winget.ps1` が担う。
