# PowerShell テスト

- 起動は必ず `Invoke-Tests.ps1`。直接 `Invoke-Pester` は使わない。
- `Install.Tests.ps1`: 実launcher・Taskfile・installerの順序、回数、失敗、再起動、引数。
- 静的解析と Windows の ANSI/BOM は CI 環境の `nix develop .#ci --command powershell-lint`。formatter の実行は既存の Nix build check で確認する。
- `TestRunner.Tests.ps1`: runner、依存の検出、0件・失敗伝播の実行時の契約。
- `Integration.Tests.ps1`: Windows profile、chezmoi反映、WSLg templateの実行時の契約。
- `lib/` は実行境界ごとにまとめ、関数・クラスごとのファイルを増やさない。CIの境界も `Install.Tests.ps1` で確認する。
- 旧仕様、プロパティ初期値、ソースの書き方、同一契約の重複テストは維持しない。
- 実インストール・ネットワーク・UACはmockし、実CLIは一時ホームへ隔離する。
- データ保護・終了コード・timeout・文字コード・0件検出を失敗にする契約は保つ。
