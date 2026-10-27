

<#
.SYNOPSIS
    WSL コマンドを実行する
.PARAMETER Arguments
    WSL に渡す引数
.OUTPUTS
    コマンドの出力
.EXAMPLE
    Invoke-Wsl -Arguments @('--list', '--quiet')
    Invoke-Wsl -Arguments @('-d', 'NixOS', '-u', 'root', '--', 'sh', '-lc', 'whoami')
#>
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

<#
.SYNOPSIS
    外部コマンドを stderr で例外化せずに実行する
.DESCRIPTION
    Windows PowerShell 5.1 は native command の stderr を ErrorRecord として扱う。
    version 表示や warning を stderr に書く正常終了コマンドを失敗扱いしないため、
    stderr は通常出力へ正規化し、成否は $LASTEXITCODE で判断する。
.PARAMETER Command
    実行するコマンド名
.PARAMETER Arguments
    コマンドに渡す引数
#>
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

<#
.SYNOPSIS
    標準 WinGet manifest を一度だけ import する
#>
function Import-WindowsPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ManifestPath
    )

    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        throw "WinGet manifest not found: $ManifestPath"
    }
    if (-not (Get-Command winget -CommandType Application -ErrorAction SilentlyContinue)) {
        throw 'WinGet executable not found.'
    }

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

<#
.SYNOPSIS
    ユーザー環境変数 PATH の現在値を返す
.DESCRIPTION
    Pester でモック可能にするため [System.Environment] を直接呼ばずにラップする
#>
function Get-UserEnvironmentPath {
    return [System.Environment]::GetEnvironmentVariable("PATH", "User")
}

<#
.SYNOPSIS
    現在の PowerShell プロセスの PATH を環境変数ストアから再構築する
.DESCRIPTION
    winget install 後は Machine/User PATH が更新されても、実行中の
    PowerShell プロセスには自動反映されない。検証コマンドを同じ
    install.cmd 実行内で見つけられるようにする。
#>
function Update-ProcessEnvironmentPath {
    [CmdletBinding()]
    param(
        [switch]$ReportStatus
    )

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
    $missingEntries = 0
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
                $missingEntries++
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
    if ($ReportStatus -and ($missingEntries -gt 0 -or $omittedEntries -gt 0)) {
        Write-Host "[INFO] Process PATH normalized: removed $missingEntries missing directories and omitted $omittedEntries over-limit entries; final length $pathLength/$maxPathLength."
    }
    if ($omittedEntries -gt 0) {
        Write-Warning "Process PATH refresh omitted $omittedEntries entries to stay within the Windows cmd.exe limit of $maxPathLength characters. Trim stale entries from the User PATH if required commands are missing."
    }
}

<#
.SYNOPSIS
    WSL が利用可能かどうかを確認する
.DESCRIPTION
    VirtualMachinePlatform の無効・未導入を先に検出する。
    wsl --status は WSL 2 を起動できない状態でも exit 0 を返すため、
    終了コードだけでは基盤の有効化を判定しない。Pester でモック可能。
.OUTPUTS
    [bool] WSL が利用可能なら $true
#>
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
        [AllowNull()]
        [string]$Argument
    )

    if ($null -eq $Argument) {
        return '""'
    }

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
