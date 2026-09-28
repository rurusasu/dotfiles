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
            $unchanged = 0
            $preserved = 0
            $failed = 0
            foreach ($pkg in $packages) {
                $wasInstalled = $this.TestPackageInstalled($pkg)
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
                $exitCode = [int]$LASTEXITCODE
                foreach ($line in $output) {
                    if (-not [string]::IsNullOrWhiteSpace([string]$line)) {
                        $this.Log("  $line", "Gray")
                    }
                }
                $installText = [string]::Join("`n", @($output))
                $isAlreadyInstalledNoOp = $installText -match "already installed|既にインストールされています|No applicable update found|No available upgrade found|No newer package versions are available|利用可能なアップグレードが見つかりませんでした|新しいパッケージ バージョンはありません"
                if ($isAlreadyInstalledNoOp -and $wasInstalled) {
                    $unchanged++
                }
                elseif ($exitCode -eq 0) {
                    $installed++
                }
                else {
                    if ($wasInstalled -and $pkg.VerifyCommand -and $this.TestPackageVerificationForPackage($pkg, $false)) {
                        $preserved++
                        $this.LogWarning("⚠ $($pkg.Id) の更新に失敗しましたが、既存のアプリケーションを維持しました (exit code: $exitCode)")
                        continue
                    }
                    $failed++
                    $this.LogWarning("✗ $($pkg.Id) のインストールに失敗しました")
                }
            }

            $messageParts = @()
            if ($installed -gt 0) { $messageParts += "$installed 個インストール" }
            if ($unchanged -gt 0) { $messageParts += "$unchanged 個変更なし" }
            if ($preserved -gt 0) { $messageParts += "$preserved 個更新失敗（既存を維持）" }
            $message = $messageParts -join ", "
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

    hidden [bool] TestPackageInstalled([object]$pkg) {
        try {
            $arguments = @("list", "-e", "--id", $pkg.Id, "--disable-interactivity")
            if ($pkg.SourceName -eq "msstore" -or $pkg.SourceName -eq "winget") {
                $arguments += @("--source", $pkg.SourceName)
            }
            $output = @(Invoke-Winget -Arguments $arguments)
            if ($LASTEXITCODE -ne 0) { return $false }
            $pattern = "(?i)(^|\s)$([regex]::Escape([string]$pkg.Id))(?=\s|$)"
            return [bool](@($output | Where-Object { [string]$_ -match $pattern }).Count)
        }
        catch {
            return $false
        }
    }

    hidden [bool] TestPackageVerificationForPackage([object]$pkg, [bool]$quiet) {
        $verifier = [WingetHandler]::new()
        return $verifier.TestPackageVerificationForPackage($pkg, $quiet)
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
                    VerifyCommand        = if ($pkg.PSObject.Properties.Name -contains "verifyCommand") { $pkg.verifyCommand } else { $null }
                }
            }
        }
        return $packages
    }

    hidden [string] GetPackagesPath([SetupContext]$ctx) {
        return Join-Path $ctx.DotfilesPath "windows\\winget\\packages.json"
    }
}
