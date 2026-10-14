[CmdletBinding()]
param([string]$RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..')))

function Initialize-WindowsInstallerRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [string]$TemporaryRoot = [IO.Path]::GetTempPath(),
        [object]$RuntimeHandler
    )

    $manifest = Get-Content -LiteralPath (Join-Path $RepositoryRoot 'windows/winget/packages.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $declarations = @(
        foreach ($source in $manifest.Sources) {
            foreach ($package in $source.Packages) {
                if ($package.PackageIdentifier -eq 'Microsoft.PowerShell') {
                    [pscustomobject]@{ Source = $source; Package = $package }
                }
            }
        }
    )
    if ($declarations.Count -ne 1 -or $declarations[0].Source.SourceDetails.Name -ne 'winget') {
        throw 'Expected exactly one Microsoft.PowerShell declaration from winget'
    }

    $temporaryBase = [IO.Path]::GetFullPath($TemporaryRoot).TrimEnd('\', '/')
    $staging = Join-Path $temporaryBase ('dotfiles-ci-powershell-' + [guid]::NewGuid().ToString('N'))
    try {
        $manifestDirectory = Join-Path $staging 'windows/winget'
        New-Item -ItemType Directory -Path $manifestDirectory -Force | Out-Null
        # Preserve all installation and verification metadata from the Windows
        # manifest. The later full installer retains this same package obligation.
        $preparationManifest = @{ Sources = @(@{
                    SourceDetails = $declarations[0].Source.SourceDetails
                    Packages      = @($declarations[0].Package)
                })
        }
        [IO.File]::WriteAllText((Join-Path $manifestDirectory 'packages.json'), ($preparationManifest | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
        if (-not ('SetupContext' -as [type])) {
            . (Join-Path $RepositoryRoot 'scripts/powershell/lib/SetupHandler.ps1')
        }
        if (-not $RuntimeHandler) {
            . (Join-Path $RepositoryRoot 'scripts/powershell/handlers/Handler.Winget.ps1')
            $RuntimeHandler = [WingetHandler]::new()
        }
        $context = [SetupContext]::new($staging)
        $context.Options['WingetProcessOnlyPath'] = $true
        $context.Options['SkipRetiredPackageCleanup'] = $true
        $context.Options['WingetRequireSuccessfulUpdate'] = $true
        if (-not $RuntimeHandler.CanApply($context)) { throw 'WinGet is unavailable for PowerShell runtime preparation' }
        $result = $RuntimeHandler.Apply($context)
        if (-not $result.Success) { throw "PowerShell runtime preparation failed: $($result.Message)" }
        Write-Host 'WINDOWS_INSTALLER_RUNTIME_READY: Microsoft.PowerShell installed and verified'
    }
    finally {
        $resolvedStaging = [IO.Path]::GetFullPath($staging)
        $expectedPrefix = $temporaryBase + [IO.Path]::DirectorySeparatorChar
        if (-not $resolvedStaging.StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Refusing to remove runtime staging outside its temporary root'
        }
        if (Test-Path -LiteralPath $resolvedStaging) { Remove-Item -LiteralPath $resolvedStaging -Recurse -Force }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    if ($PSVersionTable.PSVersion.Major -ne 5) { throw 'Prepare the MSI runtime from stable Windows PowerShell 5.1' }
    $ErrorActionPreference = 'Stop'
    Initialize-WindowsInstallerRuntime -RepositoryRoot $RepositoryRoot
}
