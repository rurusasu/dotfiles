[CmdletBinding()]
param([switch]$Check, [switch]$DeferMissing)

$ErrorActionPreference = 'Stop'

function Resolve-OmarchyGlazeWMExecutable {
    param([switch]$AllowMissing)
    $command = Get-Command glazewm.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    foreach ($relative in @('glzr.io/GlazeWM/glazewm.exe', 'GlazeWM/glazewm.exe')) {
        $candidate = Join-Path $env:ProgramFiles $relative
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    if ($AllowMissing) { return $null }
    throw 'GlazeWM executable was not found. Run the Windows dotfiles installer (glzr-io.glazewm).'
}

function Invoke-OmarchyGlazeWM {
    param([Parameter(Mandatory)][string]$Executable, [Parameter(Mandatory)][string[]]$Arguments)
    $output = & $Executable @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "GlazeWM failed ($LASTEXITCODE): $output" }
    return $output -join [Environment]::NewLine
}

function Assert-OmarchyGlazeWMResponse {
    param([Parameter(Mandatory)][string]$Response)
    $value = $Response | ConvertFrom-Json
    if (-not $value.success) { throw "GlazeWM rejected the request: $($value.error)" }
}

function Test-OmarchyGlazeWMConfig {
    param([Parameter(Mandatory)][string]$ConfigPath)
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { throw "Managed GlazeWM config was not found: $ConfigPath" }
    # The exported JSON is valid YAML. Validate deployment integrity here;
    # GlazeWM validates command/key syntax when starting or reloading.
    $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    if (-not $config.workspaces -or -not $config.workspaces[0].name) { throw 'Managed GlazeWM config requires named workspaces.' }
    if (-not $config.keybindings) { throw 'Managed GlazeWM config requires keybindings.' }
    $keys = @($config.keybindings | ForEach-Object {
            if (@($_.commands).Count -eq 0 -or @($_.bindings).Count -eq 0) { throw 'Each GlazeWM keybinding requires commands and bindings.' }
            $_.bindings
        })
    if (@($keys | Select-Object -Unique).Count -ne $keys.Count) { throw 'Managed GlazeWM config contains duplicate keys.' }
}

function Get-OmarchyGlazeWMProcess {
    $session = (Get-Process -Id $PID).SessionId
    return @(Get-CimInstance Win32_Process -Filter "Name = 'glazewm.exe'" | Where-Object SessionId -EQ $session)
}

function Test-OmarchyGlazeWMInteractiveSession {
    return [Environment]::UserInteractive -and (Get-Process -Id $PID).SessionId -ne 0 -and $env:GITHUB_ACTIONS -ne 'true'
}

function Test-OmarchyGlazeWMOwnership {
    param([Parameter(Mandatory)]$Process, [Parameter(Mandatory)][string]$Executable, [Parameter(Mandatory)][string]$ConfigPath)
    if (-not [string]::Equals($Process.ExecutablePath, $Executable, [StringComparison]::OrdinalIgnoreCase)) { return $false }
    $match = [regex]::Match([string]$Process.CommandLine, '(?:^|\s)--config(?:=|\s+)(?:"(?<path>[^"]+)"|(?<path>\S+))(?=\s|$)')
    return $match.Success -and [string]::Equals($match.Groups['path'].Value, $ConfigPath, [StringComparison]::OrdinalIgnoreCase)
}

function Set-OmarchyGlazeWMStartup {
    param([Parameter(Mandatory)][string]$StartupScript)
    $directory = Join-Path $env:APPDATA 'Microsoft/Windows/Start Menu/Programs/Startup'
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut((Join-Path $directory 'Dotfiles GlazeWM.lnk'))
    $shortcut.TargetPath = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
    $shortcut.Arguments = '-NoProfile -NonInteractive -WindowStyle Hidden -File "{0}"' -f $StartupScript
    $shortcut.WorkingDirectory = Split-Path -Parent $StartupScript
    $shortcut.Save()
}

function Start-OmarchyGlazeWM {
    param(
        [Parameter(Mandatory)][string]$Executable,
        [Parameter(Mandatory)][string]$ConfigPath,
        [Parameter(Mandatory)][string]$StartupScript
    )
    if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) { throw "GlazeWM executable was not found: $Executable" }
    Test-OmarchyGlazeWMConfig -ConfigPath $ConfigPath
    if (-not (Test-OmarchyGlazeWMInteractiveSession)) {
        Set-OmarchyGlazeWMStartup -StartupScript $StartupScript
        return 'Deferred until interactive login'
    }
    $running = @(Get-OmarchyGlazeWMProcess)
    if ($running.Count -gt 0) {
        if ($running.Count -ne 1 -or -not (Test-OmarchyGlazeWMOwnership -Process $running[0] -Executable $Executable -ConfigPath $ConfigPath)) {
            throw 'GlazeWM is already running with a different config or executable. Exit that instance from its tray menu, then apply chezmoi again.'
        }
        Assert-OmarchyGlazeWMResponse -Response (Invoke-OmarchyGlazeWM -Executable $Executable -Arguments @('command', 'wm-reload-config'))
        Set-OmarchyGlazeWMStartup -StartupScript $StartupScript
        return 'Reloaded'
    }
    $process = Start-Process -FilePath $Executable -ArgumentList ('start --config="{0}"' -f $ConfigPath) -PassThru
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    $lastFailure = 'No IPC response.'
    $ready = $false
    do {
        if ($process.HasExited) { throw 'GlazeWM exited before becoming ready. Check ~/.glzr/glazewm/errors.log.' }
        try {
            Assert-OmarchyGlazeWMResponse -Response (Invoke-OmarchyGlazeWM -Executable $Executable -Arguments @('query', 'app-metadata'))
            $ready = $true
            break
        }
        catch { $lastFailure = $_.Exception.Message }
        Start-Sleep -Milliseconds 200
    } while ([DateTime]::UtcNow -lt $deadline)
    if ($ready) {
        Set-OmarchyGlazeWMStartup -StartupScript $StartupScript
        return 'Started'
    }
    throw "GlazeWM did not become ready: $lastFailure"
}

function Initialize-OmarchyGlazeWM {
    param(
        [Parameter(Mandatory)][string]$ConfigPath,
        [Parameter(Mandatory)][string]$StartupScript,
        [switch]$DeferMissing
    )
    $executable = Resolve-OmarchyGlazeWMExecutable -AllowMissing:$DeferMissing
    if (-not $executable) {
        # Chezmoi runs before the elevated package phase on a fresh machine.
        Test-OmarchyGlazeWMConfig -ConfigPath $ConfigPath
        Set-OmarchyGlazeWMStartup -StartupScript $StartupScript
        return 'Deferred until GlazeWM installation and interactive login'
    }
    Start-OmarchyGlazeWM -Executable $executable -ConfigPath $ConfigPath -StartupScript $StartupScript
}

if ($MyInvocation.InvocationName -ne '.') {
    $configPath = Join-Path $PSScriptRoot 'config.json'
    if ($Check) { Test-OmarchyGlazeWMConfig -ConfigPath $configPath }
    else { Initialize-OmarchyGlazeWM -ConfigPath $configPath -StartupScript $PSCommandPath -DeferMissing:$DeferMissing }
}
