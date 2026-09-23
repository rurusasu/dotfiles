function Assert-WindowsInstallerSuccess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Output,

        [Parameter(Mandatory)]
        [int]$ExitCode,

        [Parameter(Mandatory)]
        [string]$CompletionMarker
    )

    if ($ExitCode -ne 0) {
        throw "Windows installer exited with code $ExitCode"
    }

    if ($Output -match '(?im)^\s*(?:\[[^\]]+\]\s*)?(?:FAIL\b|\u2717)|^\s*(?:Exception:|Admin phase skipped\.|Setup Incomplete\b|(?:User|Admin) phase failed with \d+ handler failure)') {
        throw 'Windows installer output contains a fatal or incomplete marker'
    }

    $failureSummaries = @(
        [regex]::Matches($Output, '(?m)^Total:\s*\d+\s*\|\s*Success:\s*\d+\s*\|\s*Failure:\s*(?<failures>\d+)') |
            ForEach-Object { [int]$_.Groups['failures'].Value } |
            Where-Object { $_ -gt 0 }
    )
    if ($failureSummaries.Count -gt 0) {
        $failureCount = ($failureSummaries | Measure-Object -Sum).Sum
        throw "Windows installer reported $failureCount failed handler(s)"
    }

    if ($Output.IndexOf($CompletionMarker, [StringComparison]::Ordinal) -lt 0) {
        throw "Windows installer did not reach completion marker '$CompletionMarker'"
    }
}
