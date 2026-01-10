@{
    # 除外するルール
    ExcludeRules = @(
        # dot-source で読み込む型は静的解析で認識できないため除外
        'PSUseOutputTypeCorrectly'
    )

    # 重大度でフィルタリング（Information レベルを除外）
    Severity = @('Error', 'Warning')

    # 特定のルールの設定
    Rules = @{
        # TypeNotFound は Information レベルなので Severity フィルタで除外される
        # 追加の設定が必要な場合はここに記述
    }
}
