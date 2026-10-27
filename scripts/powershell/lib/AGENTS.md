# Windows 共通処理

- `Invoke-ExternalCommand.ps1`: native実行、timeout、WSL UTF-8、昇格、プロセスPATH、標準master import。
- `Invoke-NixosWslSetup.ps1`: distro登録、同期、input更新、NixOS反映。
- 具体的な名前付き引数を使う。共有contextや結果class、未使用の互換処理は作らない。
- ユーザーPATHを永続変更しない。既存VHD・チェックアウトを削除や上書きで復旧しない。
- テストは `tests/Invoke-Tests.ps1` 経由で実行する。
