# Tests

Purpose: PowerShell ユニットテスト運用ルール（Pester v5）

## テストフレームワーク

- `Invoke-Tests.ps1` を唯一の実行エントリとして使う
- カバレッジ閾値は 80% 以上（必要に応じて `-MinimumCoverage` で指定）

## ディレクトリ構造

```
tests/
├── AGENTS.md
├── Invoke-Tests.ps1
├── Install.User.Tests.ps1
├── Install.Admin.Tests.ps1
├── Install.Orchestrator.Tests.ps1
├── Install.Tests.ps1
├── PSScriptAnalyzer.Tests.ps1
├── handlers/
│   └── Handler.*.Tests.ps1
└── lib/
    └── *.Tests.ps1
```

## テスト実行

```powershell
# tests ディレクトリで実行
.\Invoke-Tests.ps1 -MinimumCoverage 0

# 特定ファイルのみ実行
.\Invoke-Tests.ps1 -Path .\Install.User.Tests.ps1 -MinimumCoverage 0
```

## テスト作成ガイドライン

1. `It` 名は `should ...` で始める（英語・小文字）
2. 類似ケースは `-ForEach` でパラメタライズする
3. `BeforeEach` で状態を初期化する
4. 成功・失敗・境界値の分岐を最低1つずつ持つ
5. 外部コマンドは `Invoke-*` ラッパーを `Mock` する

## 補足

- `Should -Invoke` 依存より、変数トラッキング方式を優先する
- `install.ps1` の仕様変更時は `Install.User/Admin/Orchestrator` の3系統テストを同時更新する
