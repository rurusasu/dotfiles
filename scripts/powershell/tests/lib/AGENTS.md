# 共通処理の検証

`Invoke-ExternalCommand.Tests.ps1` はnative終了コード、timeout、WSL UTF-8、昇格、PATH、標準importを検証する。
`Invoke-NixosWslSetup.Tests.ps1` は登録、既存VHDの保護、同期、更新と反映の回数を検証する。
旧ラッパー、クラス、未使用互換処理のテストは追加しない。実インストールとネットワークはmockする。
