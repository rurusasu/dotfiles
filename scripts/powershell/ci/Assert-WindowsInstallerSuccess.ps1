function Assert-WindowsInstallerSuccess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Output,

        [Parameter(Mandatory)]
        [int]$ExitCode,

        [Parameter(Mandatory)]
        [string]$CompletionMarker,

        [string[]]$RequiredOutputMarkers = @()
    )

    if ($ExitCode -ne 0) {
        throw "Windows installer exited with code $ExitCode"
    }

    if ($Output -match '(?im)^\s*(?:\[[^\]]+\]\s*)?(?:FAIL\b|\u2717)|^\s*(?:Exception:|Admin phase skipped\.|Setup Incomplete\b|(?:User|Admin) phase failed with \d+ handler failure)') {
        throw 'Windows installer output contains a fatal or incomplete marker'
    }

    $summaryMatches = [regex]::Matches(
        $Output,
        '(?m)^Total:\s*(?<total>\d+)\s*\|\s*Success:\s*(?<success>\d+)\s*\|\s*Failure:\s*(?<failure>\d+)\s*$'
    )
    if ($summaryMatches.Count -ne 1) {
        throw "Windows installer must report exactly one parseable setup summary; found $($summaryMatches.Count)"
    }

    $summary = $summaryMatches[0]
    $totalCount = [int]$summary.Groups['total'].Value
    $successCount = [int]$summary.Groups['success'].Value
    $failureCount = [int]$summary.Groups['failure'].Value
    if ($totalCount -ne ($successCount + $failureCount)) {
        throw "Windows installer reported inconsistent handler counts: total=$totalCount success=$successCount failure=$failureCount"
    }
    if ($failureCount -gt 0) {
        throw "Windows installer reported $failureCount failed handler(s)"
    }

    if ($Output.IndexOf($CompletionMarker, [StringComparison]::Ordinal) -lt 0) {
        throw "Windows installer did not reach completion marker '$CompletionMarker'"
    }

    $requiredMarkers = @($RequiredOutputMarkers | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($requiredMarkers.Count -eq 0) {
        throw 'Windows installer success requires at least one required package-manager success marker'
    }

    foreach ($marker in $requiredMarkers) {
        if ($Output.IndexOf($marker, [StringComparison]::Ordinal) -lt 0) {
            throw "Windows installer output is missing required package-manager success marker: $marker"
        }
    }
}
