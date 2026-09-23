function Assert-WingetInstallSuccess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Output
    )

    $summaryMatch = [regex]::Match(
        $Output,
        '(?m)Total:\s*\d+\s*\|\s*Success:\s*\d+\s*\|\s*Failure:\s*(?<failureCount>\d+)'
    )
    if (-not $summaryMatch.Success) {
        throw 'install.cmd did not report a parseable setup summary'
    }

    $failureCount = [int]$summaryMatch.Groups['failureCount'].Value
    if ($failureCount -ne 0) {
        throw "install.cmd reported $failureCount failed setup handler(s)"
    }
    if ($Output -notmatch '(?m)^\[Winget\]\s+インストール/更新中:') {
        throw 'install.cmd did not attempt any WinGet package installations'
    }
    if ($Output -match '(?m)^\[Winget\]\s+.*✗') {
        throw 'WinGet reported one or more package installation or verification failures'
    }
}
