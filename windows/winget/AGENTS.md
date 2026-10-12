# windows/winget: パッケージ管理運用

## 編集対象

- `packages.json` を直接編集する。Windows の WinGet / Microsoft Store パッケージと installer metadata の SSOT であり、Nix からは生成しない。
- `Sources[].Packages[]` に `PackageIdentifier` と必要な `verifyCommand`、`pathEntries`、`installTimeoutSeconds`、`ciSkipInstall` などをまとめる。
- 現在の installer は Windows GUI アプリを管理する。Unix の CLI パッケージは `nix/modules/` 側で管理し、Windows manifest に自動追加しない。
- `retired-packages.json` は既存の引退パッケージ cleanup 用 manifest。通常の追加・更新は `packages.json` を編集する。

## 実行コマンド

```powershell
.\install.cmd
```

## 実装上の注意

- 一部パッケージは対話や手動操作が必要。
- 自動処理は `scripts/powershell/handlers/Handler.Winget.ps1` が担う。
