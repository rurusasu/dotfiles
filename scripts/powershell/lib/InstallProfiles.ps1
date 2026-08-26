function ConvertTo-DotfilesFeatureBoolean {
    [CmdletBinding()]
    [OutputType([bool])]
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return $false }
    if ($Value -is [bool]) { return [bool]$Value }
    if ($Value -is [System.Management.Automation.SwitchParameter]) { return [bool]$Value }

    return ([string]$Value).Trim() -match '^(1|true|yes|on)$'
}

function Resolve-DotfilesInstallOptions {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [hashtable]$Options = @{},
        [switch]$WithOllama,
        [switch]$WithDocker,
        [switch]$WithHermes
    )

    $resolved = @{}
    foreach ($key in $Options.Keys) {
        $resolved[$key] = $Options[$key]
    }

    $hermesEnabled = $WithHermes -or (ConvertTo-DotfilesFeatureBoolean $resolved['WithHermes'])
    $dockerEnabled = $hermesEnabled -or $WithDocker -or (ConvertTo-DotfilesFeatureBoolean $resolved['WithDocker'])
    $ollamaEnabled = $dockerEnabled -or $WithOllama -or (ConvertTo-DotfilesFeatureBoolean $resolved['WithOllama'])

    $resolved['WithOllama'] = [bool]$ollamaEnabled
    $resolved['WithDocker'] = [bool]$dockerEnabled
    $resolved['WithHindsight'] = [bool]$dockerEnabled
    $resolved['WithHermes'] = [bool]$hermesEnabled
    $resolved['WithChrome'] = [bool]$hermesEnabled
    $resolved['WithDiscord'] = [bool]$hermesEnabled
    $resolved['WithChromium'] = [bool]$hermesEnabled

    return $resolved
}
