# windows/winget: パッケージ管理運用

## 編集対象

- `packages.json` を直接編集する。Windows の WinGet / Microsoft Store パッケージと installer metadata の SSOT であり、Nix からは生成しない。
- `Sources[].Packages[]` に `PackageIdentifier` と必要な `verifyCommand`、`pathEntries`、`installTimeoutSeconds`、`ciSkipInstall` などをまとめる。
- 現在の installer は Windows GUI アプリを管理する。Unix の CLI パッケージは `nix/modules/` 側で管理し、Windows manifest に自動追加しない。
- `Starship.Starship` は WSL の Windows drive 上で `git_status.windows_starship` が使う補助コマンドとして管理する。ユーザー scope の ZIP portable 版を選び、`%LOCALAPPDATA%\Microsoft\WinGet\Links\starship.exe` を維持する。`persistPathEntries: true` はこの補助コマンドの PATH を次回の WSL 起動に引き継ぐための明示例外で、GUI phase でも宣言した directory をユーザー PATH に保存する。Windows PowerShell のプロンプト初期化は追加しない。
- `Git.MinGit` はこの補助コマンドが Git を呼ぶ場合の依存として管理する。ユーザー scope の ZIP portable 版の tree を保ち、同じ WinGet package directory の `cmd` を `persistPathEntries: true` で公開する。`git.exe` だけのコピーは作成しない。`pathEntriesCommand` 検証は宣言した directory の実行ファイルを使い、Codex cache などに含まれる別の Git で成功扱いにしない。
- `retired-packages.json` は既存の引退パッケージ cleanup 用 manifest。通常の追加・更新は `packages.json` を編集する。

## 実行コマンド

```powershell
.\install.cmd
```

## 実装上の注意

- 一部パッケージは対話や手動操作が必要。
- 自動処理は `scripts/powershell/handlers/Handler.Winget.ps1` が担う。
