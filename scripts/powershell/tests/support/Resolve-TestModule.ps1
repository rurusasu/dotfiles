function Resolve-TestModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Pester', 'PSScriptAnalyzer')]
        [string]$Name
    )

    $requiredCommands = if ($Name -eq 'Pester') {
        @('New-PesterConfiguration', 'Invoke-Pester')
    }
    else { @('Invoke-ScriptAnalyzer') }
    $module = Get-Module -ListAvailable -Name $Name |
        Where-Object {
            $candidate = $_
            $exportsRequiredCommands = @($requiredCommands | Where-Object {
                    -not $candidate.ExportedCommands.ContainsKey($_)
                }).Count -eq 0
            $psData = if ($candidate.PrivateData -is [Collections.IDictionary]) { $candidate.PrivateData['PSData'] } else { $null }
            $prerelease = if ($psData -is [Collections.IDictionary]) { $psData['Prerelease'] } else { $null }
            $edition = $PSVersionTable.PSEdition
            $exportsRequiredCommands -and [string]::IsNullOrWhiteSpace([string]$prerelease) -and
            ($Name -ne 'Pester' -or $candidate.Version -ge [version]'6.2') -and
            (-not $candidate.PowerShellVersion -or $candidate.PowerShellVersion -le $PSVersionTable.PSVersion) -and
            (-not $candidate.CompatiblePSEditions.Count -or $candidate.CompatiblePSEditions -contains $edition)
        } | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $module) {
        $requirement = if ($Name -eq 'Pester') { 'stable version 6.2 or newer' } else { 'stable module exporting Invoke-ScriptAnalyzer' }
        throw "Required test dependency '$Name' ($requirement) is not installed. Prepare dependencies separately; tests do not download or install them."
    }
    return $module
}
