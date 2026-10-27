

# WSL_UTF8 and the reader encoding must agree, including under Windows PowerShell 5.1.
function Invoke-Wsl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,
        [int]$TimeoutSeconds = 0
    )
    $previousWslUtf8 = $env:WSL_UTF8
    try {
        $env:WSL_UTF8 = '1'
        return Invoke-ExternalCommandWithTimeout `
            -Command "wsl" `
            -Arguments $Arguments `
            -TimeoutSeconds $TimeoutSeconds `
            -OutputEncoding ([System.Text.UTF8Encoding]::new($false))
    }
    finally { $env:WSL_UTF8 = $previousWslUtf8 }
}

# Windows PowerShell 5.1 turns native stderr into ErrorRecord objects.
# Normalize warnings to text and use LASTEXITCODE to decide success.
function Invoke-NativeCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Command,
        [string[]]$Arguments = @()
    )

    $global:LASTEXITCODE = 127
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & $Command @Arguments 2>&1 | ForEach-Object {
            if ($_ -is [System.Management.Automation.ErrorRecord]) {
                $_.Exception.Message
            }
            else {
                $_
            }
        }
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
}

function Import-WindowsPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ManifestPath
    )

    Write-Host "[Winget] Running winget import: $ManifestPath"
    Invoke-ExternalCommandWithTimeout -Command 'winget' -Arguments @(
        'import', '--import-file', $ManifestPath, '--ignore-versions',
        '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity'
    ) -TimeoutSeconds (Get-PackageInstallTimeoutSecond) | ForEach-Object { Write-Host "[Winget] $_" }
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "WinGet import failed (exit=$exitCode)."
    }
    Update-ProcessEnvironmentPath
    Write-Host '[Winget] WINGET_IMPORT_COMPLETED' -ForegroundColor Green
}

function Get-PackageInstallTimeoutSecond {
    [CmdletBinding()]
    [OutputType([int])]
    param()

    # A valid zero explicitly disables the timeout; negative values are invalid.
    $rawTimeout = $env:DOTFILES_INSTALL_TIMEOUT_SECONDS
    if (-not [string]::IsNullOrWhiteSpace($rawTimeout)) {
        $parsed = 0
        if ([int]::TryParse($rawTimeout, [ref]$parsed) -and $parsed -ge 0) {
            return $parsed
        }
    }

    return 3600
}

# Keep registry reads mockable so tests never change the persisted user PATH.
function Get-UserEnvironmentPath {
    return [System.Environment]::GetEnvironmentVariable("PATH", "User")
}

# Refresh registry PATH changes for commands launched after WinGet.
function Update-ProcessEnvironmentPath {
    [CmdletBinding()]
    param()

    $machinePath = [System.Environment]::GetEnvironmentVariable("PATH", "Machine")
    $userPath = Get-UserEnvironmentPath
    $windowsApps = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Microsoft/WindowsApps' } else { '' }
    $processPath = [System.Environment]::GetEnvironmentVariable("PATH", "Process")

    # cmd.exe rejects environment variables over 8191 characters. Since the
    # installer launches cmd.exe and Windows command aliases,
    # keep the merged PATH below that boundary instead of importing an
    # arbitrarily large registry User PATH into every child process.
    $maxPathLength = 8191
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $items = [System.Collections.Generic.List[string]]::new()
    $pathLength = 0
    $omittedEntries = 0
    # Preserve the machine PATH and entries already available to this process
    # before importing new registry User PATH entries.
    foreach ($pathValue in @($machinePath, $processPath, $userPath, $windowsApps)) {
        if ([string]::IsNullOrWhiteSpace($pathValue)) { continue }

        foreach ($item in ($pathValue -split ";")) {
            $trimmed = $item.Trim()
            if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
            $expandedPath = [System.Environment]::ExpandEnvironmentVariables($trimmed)
            $hasUnresolvedVariable = $expandedPath -match "%[^%]+%"
            $pathToUse = if ($hasUnresolvedVariable) { $trimmed } else { $expandedPath }
            if (-not $seen.Add($pathToUse)) { continue }
            if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT -and
                -not $hasUnresolvedVariable -and
                -not [System.IO.Directory]::Exists($expandedPath)) {
                continue
            }

            $nextLength = $pathLength + $pathToUse.Length
            if ($items.Count -gt 0) { $nextLength++ }
            if ($nextLength -gt $maxPathLength) {
                $omittedEntries++
                continue
            }

            $items.Add($pathToUse)
            $pathLength = $nextLength
        }
    }

    $env:PATH = $items -join ";"
    if ($omittedEntries -gt 0) {
        Write-Warning "Process PATH refresh omitted $omittedEntries entries to stay within the Windows cmd.exe limit of $maxPathLength characters. Trim stale entries from the User PATH if required commands are missing."
    }
}

# wsl --status can exit 0 even when WSL 2 cannot start.
# Reject a disabled or absent VirtualMachinePlatform before checking status.
function Test-WslAvailable {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    try {
        $feature = Get-CimInstance -ClassName Win32_OptionalFeature -Filter "Name = 'VirtualMachinePlatform'" -ErrorAction Stop
        if ($null -ne $feature -and $feature.InstallState -in @(2, 3)) {
            return $false
        }
    }
    catch {
        # CIM 非対応・照会不可の環境では従来の WSL コマンド判定に戻す。
        Write-Verbose "VirtualMachinePlatform query unavailable: $($_.Exception.Message)"
    }

    try {
        $null = Invoke-Wsl -TimeoutSeconds 5 -Arguments @("--status") 2>&1
        return $LASTEXITCODE -eq 0
    }
    catch {
        return $false
    }
}

function ConvertTo-WindowsCommandLineArgument {
    [CmdletBinding()]
    param(
        [string]$Argument
    )

    if ($Argument -notmatch '[\s"]' -and $Argument.Length -gt 0) {
        return $Argument
    }

    $builder = [System.Text.StringBuilder]::new()
    [void]$builder.Append('"')
    $backslashCount = 0

    foreach ($char in $Argument.ToCharArray()) {
        if ($char -eq '\') {
            $backslashCount++
            continue
        }

        if ($char -eq '"') {
            [void]$builder.Append('\' * (($backslashCount * 2) + 1))
            [void]$builder.Append('"')
            $backslashCount = 0
            continue
        }

        if ($backslashCount -gt 0) {
            [void]$builder.Append('\' * $backslashCount)
            $backslashCount = 0
        }
        [void]$builder.Append($char)
    }

    if ($backslashCount -gt 0) {
        [void]$builder.Append('\' * ($backslashCount * 2))
    }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function Invoke-ExternalCommandWithTimeout {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Command,
        [string[]]$Arguments = @(),
        [Parameter(Mandatory)]
        [int]$TimeoutSeconds,
        [System.Text.Encoding]$OutputEncoding = $null
    )

    $global:LASTEXITCODE = 127
    $process = $null

    try {
        $resolvedCommand = Get-Command $Command -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $resolvedCommand) {
            $global:LASTEXITCODE = 127
            return "コマンドが見つかりません: $Command"
        }
        $processStartInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $processStartInfo.FileName = $resolvedCommand.Source
        $processStartInfo.UseShellExecute = $false
        $processStartInfo.CreateNoWindow = $true
        $processStartInfo.RedirectStandardOutput = $true
        $processStartInfo.RedirectStandardError = $true
        if ($null -ne $OutputEncoding) {
            $processStartInfo.StandardOutputEncoding = $OutputEncoding
            $processStartInfo.StandardErrorEncoding = $OutputEncoding
        }
        if ($processStartInfo.GetType().GetProperty("ArgumentList")) {
            foreach ($argument in $Arguments) {
                [void]$processStartInfo.ArgumentList.Add([string]$argument)
            }
        }
        else {
            # Windows PowerShell 5.1 lacks ArgumentList; preserve CRT quote/backslash rules.
            $processStartInfo.Arguments = ($Arguments |
                    ForEach-Object { ConvertTo-WindowsCommandLineArgument -Argument ([string]$_) }) -join " "
        }

        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $processStartInfo

        [void]$process.Start()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if ($TimeoutSeconds -gt 0 -and -not $process.WaitForExit($TimeoutSeconds * 1000)) {
            try {
                if (Get-Command taskkill.exe -ErrorAction SilentlyContinue) {
                    & taskkill.exe /PID $process.Id /T /F | Out-Null
                }
                else {
                    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                }
            }
            catch {
                Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            }
            [void]$process.WaitForExit(5000)
            $global:LASTEXITCODE = 124
            $timeoutLabel = if ($Command -eq "winget") { "winget コマンド" } else { "検証コマンド" }
            $output = [System.Collections.Generic.List[string]]::new()
            foreach ($streamTask in @($stdoutTask, $stderrTask)) {
                if (-not $streamTask.Wait(2000)) { continue }
                $streamText = $streamTask.GetAwaiter().GetResult()
                if ([string]::IsNullOrEmpty($streamText)) { continue }
                foreach ($line in ($streamText -split "\r?\n")) {
                    if ($line.Length -gt 0) { $output.Add($line) }
                }
            }
            $output.Add("$timeoutLabel がタイムアウトしました (${TimeoutSeconds}s): $Command $($Arguments -join ' ')")
            return $output.ToArray()
        }
        $process.WaitForExit()

        $global:LASTEXITCODE = $process.ExitCode
        $output = [System.Collections.Generic.List[string]]::new()
        foreach ($streamText in @($stdoutTask.GetAwaiter().GetResult(), $stderrTask.GetAwaiter().GetResult())) {
            if ([string]::IsNullOrEmpty($streamText)) { continue }
            foreach ($line in ($streamText -split "\r?\n")) {
                if ($line.Length -gt 0) {
                    $output.Add($line)
                }
            }
        }
        return $output.ToArray()
    }
    catch {
        $global:LASTEXITCODE = 127
        throw
    }
    finally {
        if ($process) {
            $process.Dispose()
        }
    }
}
