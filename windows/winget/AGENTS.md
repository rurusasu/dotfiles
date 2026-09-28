# windows/winget: パッケージ管理運用

## 編集対象

- package/provider の SSOT は `nix/packages/catalog/`。Windows 専用 metadata は `nix/packages/install/windows-only.nix`。`sets.nix` は公開入口、`packages.json` は `winget-export` の生成物。
- データと installer 契約を分け、同じ package を再定義しない。分割理由・生成・反映方法は [パッケージ管理](../../docs/nix/package-management.md#分割の理由と編集先) を参照する。

## 実行コマンド

```powershell
.\install.cmd
```

## 実装上の注意

- 一部パッケージは対話や手動操作が必要。
- 自動処理は `scripts/powershell/handlers/Handler.Winget.ps1` が担う。
