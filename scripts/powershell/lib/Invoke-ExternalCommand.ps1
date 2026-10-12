<#
.SYNOPSIS
    外部コマンドのラッパー関数群

.DESCRIPTION
    外部コマンド（wsl, chezmoi, winget 等）をラップする関数群。
    Pester テストでモック可能にするため、直接呼び出しを避けて
    これらの関数を経由する。

.NOTES
    テスト時は Mock Invoke-Wsl { ... } のように使用する。
    実際のコマンド実行結果は $LASTEXITCODE で取得可能。
#>

function Invoke-WindowsInstallTaskCommand {
    [CmdletBinding()]
    param([string]$Executable, [string[]]$Arguments)
    & $Executable @Arguments
}

function Invoke-WslBaseElevation {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ScriptPath)

    $shell = Join-Path $PSHOME $(if ($PSVersionTable.PSVersion.Major -lt 6) { 'powershell.exe' } else { 'pwsh.exe' })
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ScriptPath, '-Phase', 'WslBase')
    if (Test-IsAdminSession) {
        & $shell @arguments
        return $LASTEXITCODE
    }
    $arguments[4] = '"' + $ScriptPath + '"'
    $process = Start-Process -FilePath $shell -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -Wait -PassThru
    return $process.ExitCode
}

<#
.SYNOPSIS
    WSL コマンドを実行する
.PARAMETER Arguments
    WSL に渡す引数
.OUTPUTS
    コマンドの出力
.EXAMPLE
    Invoke-Wsl --list --quiet
    Invoke-Wsl -d NixOS -u root -- sh -lc "whoami"
#>
function Invoke-Wsl {
    [CmdletBinding(PositionalBinding = $false)]
    param(
        [Parameter(Position = 0, ValueFromRemainingArguments)]
        [string[]]$Arguments,
        [int]$TimeoutSeconds = 0
    )
    if ($TimeoutSeconds -gt 0) {
        return Invoke-ExternalCommandWithTimeout `
            -Command "wsl" `
            -Arguments $Arguments `
            -TimeoutSeconds $TimeoutSeconds `
            -OutputEncoding (Get-WindowsNativeOutputEncoding)
    }
    & wsl @Arguments
}

<#
.SYNOPSIS
    dism.exe コマンドを実行する
.PARAMETER Arguments
    dism.exe に渡す引数
.OUTPUTS
    コマンドの出力
.EXAMPLE
    Invoke-Dism /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
#>
function Invoke-Dism {
    [CmdletBinding(PositionalBinding = $false)]
    param(
        [int]$TimeoutSeconds = 0,
        [Parameter(ValueFromRemainingArguments)]
        [string[]]$Arguments
    )

    if ($TimeoutSeconds -gt 0) {
        return Invoke-ExternalCommandWithTimeout `
            -Command "dism.exe" `
            -Arguments $Arguments `
            -TimeoutSeconds $TimeoutSeconds `
            -OutputEncoding (Get-WindowsNativeOutputEncoding)
    }

    & dism.exe @Arguments
}

<#
.SYNOPSIS
    chezmoi コマンドを実行する
.PARAMETER Arguments
    chezmoi に渡す引数
.OUTPUTS
    コマンドの出力
.EXAMPLE
    Invoke-Chezmoi --version
    Invoke-Chezmoi --source D:\dotfiles\chezmoi apply
#>
function Invoke-Chezmoi {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments)]
        [string[]]$Arguments,
        [string]$ExePath,
        # apply 時に chezmoi スクリプトの stderr 出力（進捗ログ等）を
        # stdout に合流させてコンソールに表示するために使用する
        [switch]$MergeStderr
    )
    if ($ExePath) {
        if ($MergeStderr) { & $ExePath @Arguments 2>&1 | ForEach-Object { Write-Host $_ } } else { & $ExePath @Arguments }
    }
    else {
        if ($MergeStderr) { & chezmoi @Arguments 2>&1 | ForEach-Object { Write-Host $_ } } else { & chezmoi @Arguments }
    }
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
    winget コマンドを実行する
.PARAMETER Arguments
    winget に渡す引数
.OUTPUTS
    コマンドの出力
.EXAMPLE
    Invoke-Winget -Arguments @("list")
    Invoke-Winget -Arguments @("import", "-i", "packages.json")
#>
function Invoke-Winget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,

        [Parameter()]
        [int]$TimeoutSeconds = -1
    )

    if ($TimeoutSeconds -lt 0) {
        $TimeoutSeconds = if ($Arguments.Count -gt 0 -and $Arguments[0] -in @("install", "upgrade")) {
            Get-PackageInstallTimeoutSecond -LegacyEnvironmentVariable "DOTFILES_WINGET_COMMAND_TIMEOUT_SECONDS"
        }
        else {
            0
        }
    }
    if ($TimeoutSeconds -gt 0) {
        return Invoke-ExternalCommandWithTimeout -Command "winget" -Arguments $Arguments -TimeoutSeconds $TimeoutSeconds
    }

    Invoke-NativeCommand -Command "winget" -Arguments $Arguments
}

function Get-PackageInstallTimeoutSecond {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter()]
        [string]$LegacyEnvironmentVariable
    )

    # Shared install override > adapter-specific legacy override > default.
    # A valid zero explicitly disables the timeout; negative values are invalid.
    $rawTimeout = $env:DOTFILES_INSTALL_TIMEOUT_SECONDS
    if (-not [string]::IsNullOrWhiteSpace($rawTimeout)) {
        $parsed = 0
        if ([int]::TryParse($rawTimeout, [ref]$parsed) -and $parsed -ge 0) {
            return $parsed
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($LegacyEnvironmentVariable)) {
        $rawTimeout = [System.Environment]::GetEnvironmentVariable($LegacyEnvironmentVariable)
        if (-not [string]::IsNullOrWhiteSpace($rawTimeout)) {
            $parsed = 0
            if ([int]::TryParse($rawTimeout, [ref]$parsed) -and $parsed -ge 0) {
                return $parsed
            }
        }
    }

    return 3600
}




<#
.SYNOPSIS
    コマンドの存在を確認する
.PARAMETER Name
    確認するコマンド名
.OUTPUTS
    コマンドが存在する場合はコマンド情報、存在しない場合は $null
.EXAMPLE
    $cmd = Get-ExternalCommand -Name "chezmoi"
    if ($cmd) { "chezmoi found at $($cmd.Source)" }
#>
function Get-ExternalCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )
    Get-Command $Name -ErrorAction SilentlyContinue
}

function Get-ExternalCommandPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$CommandInfo
    )

    if ($null -eq $CommandInfo) { return $null }
    if ($CommandInfo -is [string]) { return $CommandInfo }

    foreach ($propertyName in @('Source', 'Path')) {
        if ($CommandInfo -is [System.Collections.IDictionary] -and $CommandInfo.Contains($propertyName)) {
            $value = [string]$CommandInfo[$propertyName]
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                return $value
            }
            continue
        }

        $property = $CommandInfo.PSObject.Properties[$propertyName]
        if ($null -ne $property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) {
            return [string]$property.Value
        }
    }

    return $null
}


<#
.SYNOPSIS
    WinGet Packages から実行ファイルを検索する（全ユーザー対応）
.DESCRIPTION
    管理者昇格セッションでは $env:LOCALAPPDATA が昇格ユーザーを指すため、
    元のユーザーにインストールされたパッケージが見つからない。
    全ユーザーの AppData\Local\Microsoft\WinGet\Packages を走査して検索する。
.PARAMETER PackagePattern
    パッケージディレクトリ名のワイルドカードパターン (例: 'AgileBits.1Password.CLI*')
.PARAMETER ExeFilter
    実行ファイル名のフィルター (例: 'op.exe')
.OUTPUTS
    見つかった実行ファイルのフルパス、見つからない場合は $null
#>
function Find-WinGetExe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PackagePattern,
        [Parameter(Mandatory)]
        [string]$ExeFilter
    )
    $searchRoots = @($env:LOCALAPPDATA)
    $usersDir = Split-Path $env:USERPROFILE
    foreach ($userDir in (Get-ChildItemSafe -Path $usersDir -Directory)) {
        $otherAppData = Join-Path $userDir.FullName "AppData\Local"
        if ($otherAppData -ne $env:LOCALAPPDATA -and (Test-Path $otherAppData -ErrorAction SilentlyContinue)) {
            $searchRoots += $otherAppData
        }
    }

    foreach ($appData in $searchRoots) {
        $packagesRoot = Join-Path $appData "Microsoft\WinGet\Packages"
        if (-not (Test-Path $packagesRoot -ErrorAction SilentlyContinue)) { continue }
        $pkgDir = Get-ChildItemSafe -Path $packagesRoot -Directory |
            Where-Object { $_.Name -like $PackagePattern } |
            Select-Object -First 1
        if ($pkgDir) {
            $exe = Get-ChildItemSafe -Path $pkgDir.FullName -Filter $ExeFilter -Recurse |
                Select-Object -First 1
            if ($exe) { return $exe.FullName }
        }
    }

    return $null
}

<#
.SYNOPSIS
    パスの存在を確認する
.PARAMETER Path
    確認するパス
.OUTPUTS
    パスが存在する場合は $true、存在しない場合は $false
.EXAMPLE
    if (Test-PathExist -Path "C:\Windows") { "Exists" }
#>
function Test-PathExist {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    Test-Path -LiteralPath $Path
}



<#
.SYNOPSIS
    Release Discord's installation directory before a forced WinGet update.
.DESCRIPTION
    Stop only Discord and Update processes inside the current user's Discord
    installation. Other Squirrel updaters and Discord channels are unaffected.
    Termination errors and exit timeouts prevent the installer from starting.
#>
function Invoke-DiscordInstallPreparation {
    [CmdletBinding()]
    param()

    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        throw 'LOCALAPPDATA is required to locate the current user Discord installation.'
    }

    $discordRoot = [System.IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'Discord'))
    $discordPrefix = $discordRoot + [System.IO.Path]::DirectorySeparatorChar
    foreach ($process in @(Get-Process -ErrorAction Stop)) {
        if ($process.ProcessName -notin @('Discord', 'Update')) { continue }
        $executablePath = $process.Path
        if ([string]::IsNullOrWhiteSpace($executablePath)) { continue }
        if (-not $executablePath.StartsWith($discordPrefix, [StringComparison]::OrdinalIgnoreCase)) { continue }

        try {
            Stop-Process -Id $process.Id -Force -ErrorAction Stop
        }
        catch {
            # Discovery and termination race with Discord exiting on its own.
            if ($process.HasExited) { continue }
            throw
        }

        if (-not $process.WaitForExit(10000)) {
            throw "Discord process $($process.Id) did not exit within 10 seconds."
        }
    }
}




<#
.SYNOPSIS
    JSON ファイルを読み込む
.PARAMETER Path
    JSON ファイルパス
.OUTPUTS
    パースされたオブジェクト
.EXAMPLE
    $config = Get-JsonContent -Path ".\config.json"
#>
function Get-JsonContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
}

<#
.SYNOPSIS
    ディレクトリを作成する
.PARAMETER Path
    作成するディレクトリパス
.EXAMPLE
    New-DirectorySafe -Path "C:\temp\newdir"
#>
function New-DirectorySafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
}

<#
.SYNOPSIS
    ディレクトリ内のファイルを取得する
.PARAMETER Path
    ディレクトリパス
.PARAMETER Filter
    フィルターパターン
.PARAMETER Recurse
    再帰的に検索するか
.OUTPUTS
    ファイル情報の配列
.EXAMPLE
    Get-ChildItemSafe -Path "C:\temp" -Filter "*.ps1" -Recurse
#>
function Get-ChildItemSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [string]$Filter,
        [switch]$Recurse,
        [switch]$Directory,
        [switch]$Force
    )
    $params = @{
        LiteralPath = $Path
        ErrorAction = 'SilentlyContinue'
    }
    if ($Filter) { $params['Filter'] = $Filter }
    if ($Recurse) { $params['Recurse'] = $true }
    if ($Directory) { $params['Directory'] = $true }
    if ($Force) { $params['Force'] = $true }
    Get-ChildItem @params
}



<#
.SYNOPSIS
    Web からコンテンツをダウンロードする
.PARAMETER Uri
    ダウンロード URL
.PARAMETER OutFile
    保存先ファイルパス
.EXAMPLE
    Invoke-WebRequestSafe -Uri "https://example.com/file.zip" -OutFile "C:\temp\file.zip"
#>
function Invoke-WebRequestSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Uri,
        [Parameter(Mandatory)]
        [string]$OutFile
    )
    Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing
}

<#
.SYNOPSIS
    REST API を呼び出す
.PARAMETER Uri
    API URL
.PARAMETER Headers
    HTTP ヘッダー
.OUTPUTS
    API レスポンス
.EXAMPLE
    $response = Invoke-RestMethodSafe -Uri "https://api.github.com/repos/owner/repo/releases/latest"
#>
function Invoke-RestMethodSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Uri,
        [hashtable]$Headers = @{}
    )
    Invoke-RestMethod -Uri $Uri -Headers $Headers
}

<#
.SYNOPSIS
    指定秒数スリープする
.PARAMETER Seconds
    スリープする秒数
.EXAMPLE
    Start-SleepSafe -Seconds 5
#>
function Start-SleepSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$Seconds
    )
    Start-Sleep -Seconds $Seconds
}








<#
.SYNOPSIS
    docker コマンドを実行する
.PARAMETER Arguments
    docker に渡す引数
.OUTPUTS
    コマンドの出力
.EXAMPLE
    Invoke-Docker "ps" "--filter" "status=running"
    Invoke-Docker "compose" "-f" "path/to/docker-compose.yml" "up" "-d"
#>
function Invoke-Docker {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments)]
        [string[]]$Arguments,
        [int]$TimeoutSeconds = 0
    )
    if ($TimeoutSeconds -gt 0) {
        return Invoke-ExternalCommandWithTimeout -Command "docker" -Arguments $Arguments -TimeoutSeconds $TimeoutSeconds
    }
    & docker @Arguments
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
    ユーザー環境変数 PATH を永続的に設定する
.DESCRIPTION
    Pester でモック可能にするため [System.Environment] を直接呼ばずにラップする
#>
function Set-UserEnvironmentPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Path
    )
    if ($Path.Length -gt 32767) {
        throw "User PATH exceeds the Windows 32767-character environment-variable limit ($($Path.Length) characters)."
    }
    [System.Environment]::SetEnvironmentVariable("PATH", $Path, "User")
}

<#
.SYNOPSIS
    現在の PowerShell プロセスの PATH を環境変数ストアから再構築する
.DESCRIPTION
    winget install 後は Machine/User PATH が更新されても、実行中の
    PowerShell プロセスには自動反映されない。検証コマンドを同じ
    install.cmd 実行内で見つけられるようにする。
.PARAMETER ProcessOnly
    Refresh this process without repairing the persisted User PATH. GUI setup
    uses this mode; explicitly invoked legacy adapters retain their behavior.
#>
function Update-ProcessEnvironmentPath {
    [CmdletBinding()]
    param(
        [string[]]$ExcludePath = @(),
        [switch]$ReportStatus,
        [switch]$ProcessOnly
    )

    $machinePath = [System.Environment]::GetEnvironmentVariable("PATH", "Machine")
    $userPath = Get-UserEnvironmentPath
    $removedMissingUserEntries = 0
    $removedDuplicateUserEntries = 0
    if (-not $ProcessOnly -and -not [string]::IsNullOrWhiteSpace($userPath)) {
        $normalizedUserItems = [System.Collections.Generic.List[string]]::new()
        $normalizedUserEntries = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($userItem in ($userPath -split ";")) {
            $item = $userItem.Trim()
            if ([string]::IsNullOrWhiteSpace($item)) { continue }

            $comparisonPath = [System.Environment]::ExpandEnvironmentVariables($item.Trim('"'))
            $pathRoot = [System.IO.Path]::GetPathRoot($comparisonPath)
            if ($comparisonPath.Length -gt $pathRoot.Length) {
                $comparisonPath = $comparisonPath.TrimEnd([char[]]@("\", "/"))
            }
            if (-not $normalizedUserEntries.Add($comparisonPath)) {
                $removedDuplicateUserEntries++
                continue
            }

            # Keep missing UNC and unresolved environment-variable entries because their
            # targets may be temporarily unavailable; stale local PATH entries can never
            # resolve a command and commonly accumulate from versioned package folders.
            if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT -and
                $comparisonPath -match "^[A-Za-z]:[\\/]" -and
                $comparisonPath -notmatch "%[^%]+%") {
                $driveRoot = [System.IO.Path]::GetPathRoot($comparisonPath)
                if ((Test-Path -LiteralPath $driveRoot -PathType Container) -and
                    -not (Test-Path -LiteralPath $comparisonPath)) {
                    $removedMissingUserEntries++
                    continue
                }
            }

            $normalizedUserItems.Add($item)
        }

        $normalizedUserPath = $normalizedUserItems -join ";"
        if ($normalizedUserPath.Length -gt 32767) {
            throw "User PATH remains over the Windows 32767-character environment-variable limit after removing stale local entries ($($normalizedUserPath.Length) characters). Remove obsolete PATH entries before setup can continue."
        }
        if (-not [string]::Equals($normalizedUserPath, $userPath, [System.StringComparison]::Ordinal)) {
            Set-UserEnvironmentPath -Path $normalizedUserPath
            $userPath = $normalizedUserPath
            if ($ReportStatus) {
                Write-Host "[INFO] User PATH repaired: removed $removedMissingUserEntries missing local directories and $removedDuplicateUserEntries duplicate entries; final length $($userPath.Length)/32767."
            }
        }
    }
    $processPath = [System.Environment]::GetEnvironmentVariable("PATH", "Process")

    # cmd.exe rejects environment variables over 8191 characters. Since the
    # installer launches .cmd shims (npm, pnpm, corepack, and winget aliases),
    # keep the merged PATH below that boundary instead of importing an
    # arbitrarily large registry User PATH into every child process.
    $maxPathLength = 8191
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $items = [System.Collections.Generic.List[string]]::new()
    $pathLength = 0
    $omittedEntries = 0
    $missingEntries = 0
    $excluded = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $ExcludePath) {
        if (-not [string]::IsNullOrWhiteSpace($entry)) {
            $expandedEntry = [System.Environment]::ExpandEnvironmentVariables($entry.Trim())
            [void]$excluded.Add($expandedEntry)
        }
    }

    # Preserve the machine PATH and entries already available to this process
    # before importing new registry User PATH entries.
    foreach ($pathValue in @($machinePath, $processPath, $userPath)) {
        if ([string]::IsNullOrWhiteSpace($pathValue)) { continue }

        foreach ($item in ($pathValue -split ";")) {
            $trimmed = $item.Trim()
            if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
            $expandedPath = [System.Environment]::ExpandEnvironmentVariables($trimmed)
            $hasUnresolvedVariable = $expandedPath -match "%[^%]+%"
            $pathToUse = if ($hasUnresolvedVariable) { $trimmed } else { $expandedPath }
            if ($excluded.Contains($pathToUse)) { continue }
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
        $null = Invoke-Wsl -TimeoutSeconds (Get-WslCheckTimeoutSecond) "--status" 2>&1
        return $LASTEXITCODE -eq 0
    }
    catch {
        return $false
    }
}

function Get-WslCheckTimeoutSecond {
    [CmdletBinding()]
    [OutputType([int])]
    param()

    $timeoutSeconds = 5
    $rawTimeout = $env:DOTFILES_WSL_CHECK_TIMEOUT_SECONDS
    if (-not [string]::IsNullOrWhiteSpace($rawTimeout)) {
        $parsed = 0
        if ([int]::TryParse($rawTimeout, [ref]$parsed) -and $parsed -gt 0) {
            $timeoutSeconds = $parsed
        }
    }
    return $timeoutSeconds
}

function Get-WslInstallTimeoutSecond {
    [CmdletBinding()]
    [OutputType([int])]
    param()

    return Get-PackageInstallTimeoutSecond -LegacyEnvironmentVariable "DOTFILES_WSL_INSTALL_TIMEOUT_SECONDS"
}

function Get-WindowsNativeOutputEncoding {
    [CmdletBinding()]
    [OutputType([System.Text.Encoding])]
    param()

    $rawEncoding = $env:DOTFILES_WINDOWS_NATIVE_OUTPUT_ENCODING
    if (-not [string]::IsNullOrWhiteSpace($rawEncoding)) {
        try {
            return [System.Text.Encoding]::GetEncoding($rawEncoding)
        }
        catch {
            Write-Warning "Invalid DOTFILES_WINDOWS_NATIVE_OUTPUT_ENCODING '$rawEncoding'. Falling back to the Windows OEM code page."
        }
    }

    $isWindowsRuntime = $true
    $isWindowsVariable = Get-Variable -Name IsWindows -Scope Global -ErrorAction SilentlyContinue
    if ($null -ne $isWindowsVariable) {
        $isWindowsRuntime = [bool]$isWindowsVariable.Value
    }
    elseif ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
        $isWindowsRuntime = $false
    }

    if (-not $isWindowsRuntime) {
        return [System.Text.Encoding]::UTF8
    }

    try {
        $providerType = [type]::GetType("System.Text.CodePagesEncodingProvider, System.Text.Encoding.CodePages")
        if ($null -ne $providerType) {
            $provider = $providerType.GetProperty("Instance").GetValue($null)
            [System.Text.Encoding]::RegisterProvider($provider)
        }
    }
    catch {
        Write-Verbose "Code page encoding provider registration was skipped: $($_.Exception.Message)"
    }

    $codePage = [System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage
    return [System.Text.Encoding]::GetEncoding($codePage)
}

<#
.SYNOPSIS
    現在のセッションが管理者権限で実行されているか確認する
.DESCRIPTION
    Windows Principal を使って管理者ロールを確認する。
    権限確認で例外が発生した場合は安全側に倒して $false を返す。
#>
function Test-IsAdminSession {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    try {
        $principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
        return $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
    }
    catch {
        return $false
    }
}

<#
.SYNOPSIS
    任意の外部コマンドを実行する（verifyCommand 用）
.DESCRIPTION
    パッケージインストール後の動作検証に使用。
    packages.json の verifyCommand.command を実行する。
.PARAMETER Command
    実行するコマンド名
.PARAMETER Arguments
    コマンドに渡す引数
.OUTPUTS
    コマンドの出力
.EXAMPLE
    Invoke-VerifyCommand -Command "qmd" -Arguments @("status")
#>
function Invoke-VerifyCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Command,
        [string[]]$Arguments = @(),
        [int]$TimeoutSeconds = 0
    )

    if ($TimeoutSeconds -gt 0) {
        return Invoke-VerifyCommandWithTimeout -Command $Command -Arguments $Arguments -TimeoutSeconds $TimeoutSeconds
    }

    Invoke-NativeCommand -Command $Command -Arguments $Arguments
}

function Invoke-VerifyCommandWithTimeout {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Command,
        [string[]]$Arguments = @(),
        [Parameter(Mandatory)]
        [int]$TimeoutSeconds
    )

    Invoke-ExternalCommandWithTimeout -Command $Command -Arguments $Arguments -TimeoutSeconds $TimeoutSeconds
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
        $filePath = $Command
        $argumentList = @($Arguments)
        $resolvedCommand = Get-Command $Command -ErrorAction SilentlyContinue
        if (-not $resolvedCommand) {
            $global:LASTEXITCODE = 127
            return "コマンドが見つかりません: $Command"
        }
        $resolvedCommandPath = Get-ExternalCommandPath -CommandInfo $resolvedCommand
        if ($resolvedCommandPath -like "*.ps1") {
            $psExe = if (Get-Command pwsh -ErrorAction SilentlyContinue) { "pwsh" } else { "powershell.exe" }
            $filePath = $psExe
            $argumentList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $resolvedCommandPath) + @($Arguments)
        }
        elseif ($resolvedCommandPath) {
            $filePath = $resolvedCommandPath
        }

        $processStartInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $processStartInfo.FileName = $filePath
        $processStartInfo.UseShellExecute = $false
        $processStartInfo.CreateNoWindow = $true
        $processStartInfo.RedirectStandardOutput = $true
        $processStartInfo.RedirectStandardError = $true
        if ($null -ne $OutputEncoding) {
            $processStartInfo.StandardOutputEncoding = $OutputEncoding
            $processStartInfo.StandardErrorEncoding = $OutputEncoding
        }
        if ($processStartInfo.GetType().GetProperty("ArgumentList")) {
            foreach ($argument in @($argumentList)) {
                [void]$processStartInfo.ArgumentList.Add([string]$argument)
            }
        }
        else {
            $processStartInfo.Arguments = (@($argumentList) |
                    ForEach-Object { ConvertTo-WindowsCommandLineArgument -Argument ([string]$_) }) -join " "
        }

        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $processStartInfo

        [void]$process.Start()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
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

