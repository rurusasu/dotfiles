@{
    # 除外するルール
    ExcludeRules = @(
        # dot-source で読み込む型は静的解析で認識できないため除外
        'PSUseOutputTypeCorrectly',
        # BOM エンコーディングは UTF-8 (without BOM) でも問題ないため除外
        'PSUseBOMForUnicodeEncodedFile',
        # 外部コマンドラッパー関数では ShouldProcess は不要なため除外
        'PSUseShouldProcessForStateChangingFunctions',
        # ハンドラーオーケストレーション関数では Write-Host でユーザーに直接出力するため除外
        'PSAvoidUsingWriteHost'
    )

    # 重大度でフィルタリング（Information レベルを除外）
    # TypeNotFound は Information レベルで、using module の制限によるパースエラーなので無視
    Severity = @('Error', 'Warning')

    # 特定のルールの設定
    Rules = @{
        # PSAvoidUsingCmdletAliases のカスタム設定例
        PSAvoidUsingCmdletAliases = @{
            # 許容するエイリアス（必要に応じて追加）
            allowlist = @()
        }
    }
}
