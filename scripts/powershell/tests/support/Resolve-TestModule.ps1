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
            $edition = if ($PSVersionTable.ContainsKey('PSEdition')) { $PSVersionTable.PSEdition } else { 'Desktop' }
            $exportsRequiredCommands -and [string]::IsNullOrWhiteSpace([string]$prerelease) -and
            (-not $candidate.PowerShellVersion -or $candidate.PowerShellVersion -le $PSVersionTable.PSVersion) -and
            (-not $candidate.CompatiblePSEditions.Count -or $candidate.CompatiblePSEditions -contains $edition)
        } | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $module) {
        throw "Required test dependency '$Name' (stable module exporting $($requiredCommands -join ', ')) is not installed. Prepare dependencies separately; tests do not download or install them."
    }
    return $module
}

function Assert-PesterCoverageConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Configuration,
        [Parameter(Mandatory)][System.Management.Automation.PSModuleInfo]$Module
    )

    $coverageConfiguration = $Configuration.PSObject.Properties['CodeCoverage']
    if (-not $coverageConfiguration -or $null -eq $coverageConfiguration.Value -or
        -not $coverageConfiguration.Value.PSObject.Properties['UseBreakpoints']) {
        throw "Required test dependency 'Pester' does not provide CodeCoverage.UseBreakpoints. Prepare dependencies separately; tests do not download or install them."
    }

    $coberturaExporter = & $Module {
        Get-Command -Name Get-CoberturaReportXml -CommandType Function -ErrorAction SilentlyContinue
    }
    if (-not $coberturaExporter) {
        throw "Required test dependency 'Pester' does not provide the Cobertura coverage exporter. Prepare dependencies separately; tests do not download or install them."
    }
}
