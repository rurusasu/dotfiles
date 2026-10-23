function Resolve-TestModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Pester', 'PSScriptAnalyzer')]
        [string]$Name
    )

    # Pester's output/coverage configuration requires the modern configuration
    # API; the Windows inbox Pester 3.x does not provide it.
    $minimumVersion = if ($Name -eq 'Pester') { [Version]'5.9.0' } else { [Version]'1.0.0' }
    $module = Get-Module -ListAvailable -Name $Name |
        Where-Object {
            $psData = if ($_.PrivateData -is [Collections.IDictionary]) { $_.PrivateData['PSData'] } else { $null }
            $prerelease = if ($psData -is [Collections.IDictionary]) { $psData['Prerelease'] } else { $null }
            $edition = if ($PSVersionTable.ContainsKey('PSEdition')) { $PSVersionTable.PSEdition } else { 'Desktop' }
            $_.Version -ge $minimumVersion -and [string]::IsNullOrWhiteSpace([string]$prerelease) -and
            (-not $_.PowerShellVersion -or $_.PowerShellVersion -le $PSVersionTable.PSVersion) -and
            (-not $_.CompatiblePSEditions.Count -or $_.CompatiblePSEditions -contains $edition)
        } | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $module) {
        throw "Required test dependency '$Name' (stable version >= $minimumVersion) is not installed. Prepare dependencies separately; tests do not download or install them."
    }
    return $module
}
