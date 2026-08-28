function ConvertTo-DotfilesFeatureBoolean {
    [CmdletBinding()]
    [OutputType([bool])]
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return $false }
    if ($Value -is [bool]) { return [bool]$Value }
    if ($Value -is [System.Management.Automation.SwitchParameter]) { return [bool]$Value }

    return ([string]$Value).Trim() -match '^(1|true|yes|on)$'
}

function Resolve-DotfilesInstallOption {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [hashtable]$Options = @{},
        [switch]$WithOllama,
        [switch]$WithDocker,
        [switch]$WithMLflow,
        [switch]$WithHindsight,
        [switch]$WithHermes
    )

    $resolved = @{}
    foreach ($key in $Options.Keys) {
        $resolved[$key] = $Options[$key]
    }

    $hermesRequested = $WithHermes -or (ConvertTo-DotfilesFeatureBoolean $resolved['WithHermes'])
    $hindsightRequested = $WithHindsight -or (ConvertTo-DotfilesFeatureBoolean $resolved['WithHindsight'])
    $mlflowRequested = $WithMLflow -or (ConvertTo-DotfilesFeatureBoolean $resolved['WithMLflow'])
    $dockerRequested = $WithDocker -or (ConvertTo-DotfilesFeatureBoolean $resolved['WithDocker'])
    $ollamaRequested = $WithOllama -or (ConvertTo-DotfilesFeatureBoolean $resolved['WithOllama'])

    # 依存関係は上位サービスから下位サービスへ閉包する。
    # 個別フラグだけを指定した場合は、指定したサービス自身だけを有効にする。
    $hermesEnabled = [bool]$hermesRequested
    $hindsightEnabled = [bool]($hindsightRequested -or $hermesEnabled)
    $mlflowEnabled = [bool]($mlflowRequested -or $hindsightEnabled)
    $dockerEnabled = [bool]($dockerRequested -or $mlflowEnabled)
    $ollamaEnabled = [bool]($ollamaRequested -or $mlflowEnabled)

    $resolved['WithOllama'] = [bool]$ollamaEnabled
    $resolved['WithDocker'] = [bool]$dockerEnabled
    $resolved['WithMLflow'] = [bool]$mlflowEnabled
    $resolved['WithHindsight'] = [bool]$hindsightEnabled
    $resolved['WithHermes'] = [bool]$hermesEnabled
    $resolved['WithChrome'] = [bool]$hermesEnabled
    $resolved['WithDiscord'] = [bool]$hermesEnabled
    $resolved['WithChromium'] = [bool]$hermesEnabled

    return $resolved
}
