# PowerShell テスト

- 起動は必ず `Invoke-Tests.ps1`。直接 `Invoke-Pester` は使わない。
- `Install.Tests.ps1`: 実launcher・Taskfile・installerの順序、回数、失敗、再起動、引数。
- `PowerShell.Tests.ps1`: 実静的解析、ANSI/BOM、formatterの実行。
- `TestRunner.Tests.ps1`: runner、coverage、失敗伝播の実行時の契約。
- `lib/` は実行境界ごとにまとめ、関数・クラスごとのファイルを増やさない。CIの境界も `Install.Tests.ps1` で確認する。
- 旧仕様、プロパティ初期値、ソースの書き方、同一契約の重複テストは維持しない。
- 実インストール・ネットワーク・UACはmockし、実CLIは一時ホームへ隔離する。
- データ保護・終了コード・timeout・文字コード・0件検出を失敗にする契約は保つ。
