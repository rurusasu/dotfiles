#Requires -Module Pester

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    $script:runsOnWindows = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
}

function Stop-TestProcessTree {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$ProcessId
    )

    if (Get-Command taskkill.exe -ErrorAction SilentlyContinue) {
        & taskkill.exe /PID $ProcessId /T /F | Out-Null
        return
    }

    Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
}

Describe 'install.cmd entrypoint' {
    It 'should execute install.ps1 directly and return before timeout' {
        if (-not $script:runsOnWindows) {
            Set-ItResult -Skipped -Because "install.cmd is a Windows entrypoint"
            return
        }

        $workDir = Join-Path $TestDrive "install-cmd"
        $scriptDir = Join-Path $workDir "scripts\powershell"
        New-Item -ItemType Directory -Path $scriptDir -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:repoRoot "install.cmd") -Destination (Join-Path $workDir "install.cmd")

        $stubInstall = @'
[CmdletBinding()]
param(
    [switch]$NoPause,
    [switch]$UserPhaseOnly,
    [string]$Sentinel = ""
)

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$marker = Join-Path $repoRoot "install-marker.txt"
$message = "STUB_INSTALL_COMPLETE NoPause=$NoPause UserPhaseOnly=$UserPhaseOnly Sentinel=$Sentinel"
[System.IO.File]::WriteAllText($marker, $message, [System.Text.UTF8Encoding]::new($false))
Write-Host $message
exit 0
'@
        [System.IO.File]::WriteAllText(
            (Join-Path $scriptDir "install.ps1"),
            $stubInstall,
            [System.Text.UTF8Encoding]::new($false)
        )

        $stdoutPath = Join-Path $workDir "stdout.txt"
        $stderrPath = Join-Path $workDir "stderr.txt"
        $process = Start-Process -FilePath "cmd.exe" `
            -ArgumentList @("/d", "/c", "install.cmd", "-NoPause", "-UserPhaseOnly", "-Sentinel", "ok") `
            -WorkingDirectory $workDir `
            -RedirectStandardOutput $stdoutPath `
            -RedirectStandardError $stderrPath `
            -WindowStyle Hidden `
            -PassThru

        try {
            $finished = $process.WaitForExit(20000)
            if (-not $finished) {
                Stop-TestProcessTree -ProcessId $process.Id
                $stdout = if (Test-Path -LiteralPath $stdoutPath) { Get-Content -LiteralPath $stdoutPath -Raw } else { "" }
                $stderr = if (Test-Path -LiteralPath $stderrPath) { Get-Content -LiteralPath $stderrPath -Raw } else { "" }
                throw "install.cmd timed out. stdout=[$stdout] stderr=[$stderr]"
            }

            $process.ExitCode | Should -Be 0
            $marker = Get-Content -LiteralPath (Join-Path $workDir "install-marker.txt") -Raw
            $marker | Should -Match "STUB_INSTALL_COMPLETE"
            $marker | Should -Match "NoPause=True"
            $marker | Should -Match "UserPhaseOnly=True"
            $marker | Should -Match "Sentinel=ok"
        }
        finally {
            if (-not $process.HasExited) {
                Stop-TestProcessTree -ProcessId $process.Id
            }
        }
    }

    It 'should drive the real install.ps1 orchestrator through Phase 2a and final completion' {
        if (-not $script:runsOnWindows) {
            Set-ItResult -Skipped -Because "install.cmd is a Windows entrypoint"
            return
        }

        $workDir = Join-Path $TestDrive "install-cmd-orchestrator"
        $scriptDir = Join-Path $workDir "scripts\powershell"
        $libDir = Join-Path $scriptDir "lib"
        New-Item -ItemType Directory -Path $scriptDir -Force | Out-Null
        New-Item -ItemType Directory -Path $libDir -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:repoRoot "install.cmd") -Destination (Join-Path $workDir "install.cmd")
        Copy-Item -LiteralPath (Join-Path $script:repoRoot "scripts\powershell\install.ps1") -Destination (Join-Path $scriptDir "install.ps1")
        Copy-Item -LiteralPath (Join-Path $script:repoRoot "scripts\powershell\lib\WindowsEnvironment.ps1") -Destination (Join-Path $libDir "WindowsEnvironment.ps1")

        $stubUser = @'
[CmdletBinding()]
param(
    [string]$DistroName = "NixOS",
    [string]$InstallDir = "",
    [string]$ReleaseTag = "",
    [string]$PostInstallScript = "",
    [hashtable]$Options = @{},
    [string]$SyncMode = "link",
    [string]$SyncBack = "lock"
)
Write-Host "STUB_USER_PHASE_COMPLETE"
exit 0
'@
        $stubAdmin = @'
[CmdletBinding()]
param(
    [string]$DistroName = "NixOS",
    [string]$InstallDir = "",
    [string]$ReleaseTag = "",
    [string]$PostInstallScript = "",
    [hashtable]$Options = @{},
    [string]$OptionsJson = "",
    [string]$SyncMode = "link",
    [string]$SyncBack = "lock",
    [switch]$CheckOnly,
    [string]$LogFile = "",
    [Nullable[bool]]$AdminOnly = $null
)
if ($CheckOnly) {
    Write-Output $false
    exit 0
}
if ($AdminOnly -eq $false) {
    Write-Host "STUB_PHASE2A_COMPLETE"
    exit 0
}
Write-Host "STUB_ADMIN_PHASE_COMPLETE"
exit 0
'@
        [System.IO.File]::WriteAllText((Join-Path $scriptDir "install.user.ps1"), $stubUser, [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::WriteAllText((Join-Path $scriptDir "install.admin.ps1"), $stubAdmin, [System.Text.UTF8Encoding]::new($false))

        $stdoutPath = Join-Path $workDir "stdout.txt"
        $stderrPath = Join-Path $workDir "stderr.txt"
        $process = Start-Process -FilePath "cmd.exe" `
            -ArgumentList @("/d", "/c", "install.cmd", "-NoPause") `
            -WorkingDirectory $workDir `
            -RedirectStandardOutput $stdoutPath `
            -RedirectStandardError $stderrPath `
            -WindowStyle Hidden `
            -PassThru

        try {
            $finished = $process.WaitForExit(20000)
            if (-not $finished) {
                Stop-TestProcessTree -ProcessId $process.Id
                $stdout = if (Test-Path -LiteralPath $stdoutPath) { Get-Content -LiteralPath $stdoutPath -Raw } else { "" }
                $stderr = if (Test-Path -LiteralPath $stderrPath) { Get-Content -LiteralPath $stderrPath -Raw } else { "" }
                throw "install.cmd orchestrator timed out. stdout=[$stdout] stderr=[$stderr]"
            }

            $stdoutText = Get-Content -LiteralPath $stdoutPath -Raw
            $process.ExitCode | Should -Be 0
            $stdoutText | Should -Match "STUB_USER_PHASE_COMPLETE"
            $stdoutText | Should -Match "Phase 2a: Non-Admin Setup"
            $stdoutText | Should -Match "STUB_PHASE2A_COMPLETE"
            $stdoutText | Should -Match "Setup Complete!"
        }
        finally {
            if (-not $process.HasExited) {
                Stop-TestProcessTree -ProcessId $process.Id
            }
        }
    }
}
