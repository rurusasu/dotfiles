<#
.SYNOPSIS
    Administrator-only winget package handler.

.DESCRIPTION
    Installs only packages marked requiresAdmin in the generated winget
    manifest. The normal WingetHandler remains user-scoped and defers these
    packages so install.user.ps1 never invokes a machine-scope installer.
#>

$libPath = Split-Path -Parent $PSScriptRoot
. (Join-Path $libPath "lib\Invoke-ExternalCommand.ps1")

class WingetAdminHandler : SetupHandlerBase {
    WingetAdminHandler() {
        $this.Name = "WingetAdmin"
        $this.Description = "winget 管理者パッケージ管理"
        $this.Order = 6
        $this.RequiresAdmin = $true
        $this.Phase = 2
    }

    [bool] CanApply([SetupContext]$ctx) {
        $wingetCmd = Get-ExternalCommand -Name "winget"
        if (-not $wingetCmd) {
            $this.LogWarning("winget が見つかりません")
            return $false
        }

        $packagesPath = $this.GetPackagesPath($ctx)
        if (-not (Test-PathExist -Path $packagesPath)) {
            $this.LogWarning("パッケージリストが見つかりません: $packagesPath")
            return $false
        }

        return $this.GetAdministratorPackages($ctx).Count -gt 0
    }

    [SetupResult] Apply([SetupContext]$ctx) {
        try {
            $packages = $this.GetAdministratorPackages($ctx)
            if ($packages.Count -eq 0) {
                return $this.CreateSuccessResult("管理者パッケージはありません")
            }

            $installed = 0
            $failed = 0
            foreach ($pkg in $packages) {
                $installArguments = @(
                    "install", "-e", "--id", $pkg.Id,
                    "--silent",
                    "--accept-package-agreements",
                    "--accept-source-agreements",
                    "--disable-interactivity"
                )
                if ($pkg.SourceName -eq "msstore") {
                    $installArguments += "--source"
                    $installArguments += "msstore"
                }
                elseif ($pkg.SourceName -eq "winget") {
                    $installArguments += "--source"
                    $installArguments += "winget"
                }
                if ($pkg.InstallArgs) { $installArguments += @($pkg.InstallArgs) }

                $this.Log("インストール/更新中: $($pkg.Id)")
                $timeout = if ($pkg.InstallTimeoutSeconds) { [int]$pkg.InstallTimeoutSeconds } else { 0 }
                if ($timeout -gt 0) {
                    $output = @(Invoke-Winget -Arguments $installArguments -TimeoutSeconds $timeout)
                }
                else {
                    $output = @(Invoke-Winget -Arguments $installArguments)
                }
                foreach ($line in $output) {
                    if (-not [string]::IsNullOrWhiteSpace([string]$line)) {
                        $this.Log("  $line", "Gray")
                    }
                }
                if ($LASTEXITCODE -eq 0 -or ($output -join "`n") -match "already installed|既にインストールされています|No applicable update found") {
                    $installed++
                }
                else {
                    $failed++
                    $this.LogWarning("✗ $($pkg.Id) のインストールに失敗しました")
                }
            }

            $message = "$installed 個インストール"
            if ($failed -gt 0) {
                $message += ", $failed 個失敗"
                return $this.CreateFailureResult($message)
            }
            return $this.CreateSuccessResult($message)
        }
        catch {
            return $this.CreateFailureResult($_.Exception.Message, $_.Exception)
        }
    }

    hidden [object[]] GetAdministratorPackages([SetupContext]$ctx) {
        $packagesPath = $this.GetPackagesPath($ctx)
        $packagesJson = Get-JsonContent -Path $packagesPath
        $packages = @()
        foreach ($source in $packagesJson.Sources) {
            $sourceName = if ($source.SourceDetails) { [string]$source.SourceDetails.Name } else { "" }
            foreach ($pkg in @($source.Packages)) {
                if (-not $pkg.PackageIdentifier) { continue }
                $requiresAdmin = $pkg.PSObject.Properties.Name -contains "requiresAdmin" -and [bool]$pkg.requiresAdmin
                if (-not $requiresAdmin) { continue }
                $skipInstall = $pkg.PSObject.Properties.Name -contains "skipInstall" -and [bool]$pkg.skipInstall
                if ($skipInstall) { continue }
                $installFeature = if ($pkg.PSObject.Properties.Name -contains "installFeature") {
                    [string]$pkg.installFeature
                }
                else {
                    ""
                }
                if ($installFeature -and -not [bool]$ctx.GetOption($installFeature, $false)) { continue }
                $installTimeoutSeconds = if ($pkg.PSObject.Properties.Name -contains "installTimeoutSeconds") {
                    $pkg.installTimeoutSeconds
                }
                else {
                    $null
                }
                $installArgs = if ($pkg.PSObject.Properties.Name -contains "installArgs") {
                    @($pkg.installArgs)
                }
                else {
                    @()
                }
                $packages += [PSCustomObject]@{
                    Id                    = [string]$pkg.PackageIdentifier
                    SourceName            = $sourceName
                    InstallArgs           = $installArgs
                    InstallTimeoutSeconds = $installTimeoutSeconds
                }
            }
        }
        return $packages
    }

    hidden [string] GetPackagesPath([SetupContext]$ctx) {
        return Join-Path $ctx.DotfilesPath "windows\\winget\\packages.json"
    }
}
