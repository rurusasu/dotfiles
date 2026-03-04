# tests: PowerShell テスト実行基準

## 実行ルール

- テスト起動は必ず `Invoke-Tests.ps1` を使う。
- 直接 `Invoke-Pester` は使わない。

## よく使う実行コマンド

```powershell
cd scripts/powershell/tests
.\Invoke-Tests.ps1
.\Invoke-Tests.ps1 -All -IncludeBats
.\Invoke-Tests.ps1 -Path .\handlers\Handler.Docker.Tests.ps1 -MinimumCoverage 0
```

```powershell
task test:powershell
```

## テスト実装ルール

1. `Handler.*.ps1` には対応する `Handler.*.Tests.ps1` を作る。
2. 外部コマンドはラッパー関数を `Mock` する。
3. `Should -Invoke` 依存よりも変数トラッキングを優先する。
4. 成功系・失敗系・スキップ条件を分けて検証する。
