function Assert-WingetInstallSuccess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Output,
        [string[]]$ExpectedPackageIds = @()
    )

    $summaryMatch = [regex]::Match(
        $Output,
        '(?m)Total:\s*\d+\s*\|\s*Success:\s*\d+\s*\|\s*Failure:\s*(?<failureCount>\d+)'
    )
    if (-not $summaryMatch.Success) {
        throw 'install.cmd did not report a parseable setup summary'
    }

    $timeoutDiagnostics = @([regex]::Matches($Output, '(?m)^\[Winget\][ \t]+TIMEOUT_DIAGNOSTIC:[ \t]*(?<diagnostic>[^\r\n]+)\r?$') |
            ForEach-Object { $_.Groups['diagnostic'].Value })
    $failureCount = [int]$summaryMatch.Groups['failureCount'].Value
    if ($failureCount -ne 0) {
        $diagnosticSummary = if ($timeoutDiagnostics.Count -gt 0) { "; WinGet timeout diagnostics: $($timeoutDiagnostics -join ' | ')" } else { "" }
        throw "install.cmd reported $failureCount failed setup handler(s)$diagnosticSummary"
    }
    if ($Output -match '(?m)^\[Winget\]\s+.*✗') {
        throw 'WinGet reported one or more package installation or verification failures'
    }

    $inventoryMatch = [regex]::Match($Output, '(?m)^\[Winget\][ \t]+CI_VERIFICATION_INVENTORY:[ \t]*(?<ids>[^\r\n]*)\r?$')
    if (-not $inventoryMatch.Success) {
        throw 'install.cmd did not report the WinGet CI verification inventory'
    }
    $expectedIds = @($inventoryMatch.Groups['ids'].Value -split '\|' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($expectedIds.Count -eq 0) {
        throw 'install.cmd reported an empty WinGet CI verification inventory'
    }
    if (@($expectedIds | Select-Object -Unique).Count -ne $expectedIds.Count) {
        throw 'install.cmd reported duplicate package IDs in the WinGet CI verification inventory'
    }

    $expectedSet = @{}
    foreach ($id in $expectedIds) { $expectedSet[$id] = $true }
    if ($ExpectedPackageIds.Count -gt 0) {
        $requiredSet = @{}
        foreach ($id in $ExpectedPackageIds) { $requiredSet[$id] = $true }
        $missingExpectedIds = @($ExpectedPackageIds | Select-Object -Unique | Where-Object { -not $expectedSet.ContainsKey($_) })
        if ($missingExpectedIds.Count -gt 0) {
            throw "expected Windows E2E packages are missing from the verification inventory: $($missingExpectedIds -join ', ')"
        }
        $unexpectedInventoryIds = @($expectedIds | Where-Object { -not $requiredSet.ContainsKey($_) })
        if ($unexpectedInventoryIds.Count -gt 0) {
            throw "verification inventory contains packages outside the Windows E2E scope: $($unexpectedInventoryIds -join ', ')"
        }
    }

    $successMatches = [regex]::Matches(
        $Output,
        '(?m)^\[Winget\]\s+(?:✓\s+|検証済み:\s+|スキップ \(検証済み\):\s+)(?<id>[\w.+-]+)(?:\s|\(|$)'
    )
    $successfulIds = @($successMatches | ForEach-Object { $_.Groups['id'].Value } | Select-Object -Unique)
    $successfulSet = @{}
    foreach ($id in $successfulIds) { $successfulSet[$id] = $true }

    $missingIds = @($expectedIds | Where-Object { -not $successfulSet.ContainsKey($_) })
    if ($missingIds.Count -gt 0) {
        throw "WinGet verification did not succeed for every inventory package; missing: $($missingIds -join ', ')"
    }
    $unexpectedIds = @($successfulIds | Where-Object { -not $expectedSet.ContainsKey($_) })
    if ($unexpectedIds.Count -gt 0) {
        throw "WinGet reported successful package IDs outside its CI inventory: $($unexpectedIds -join ', ')"
    }
    if ($Output -match '(?m)^\[Winget\].*実行検証をスキップ') {
        throw 'WinGet skipped execution verification for a timed-out package in CI'
    }
}
