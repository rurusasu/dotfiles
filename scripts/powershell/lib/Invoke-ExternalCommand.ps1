<#
.SYNOPSIS
    外部コマンドのラッパー関数群

.DESCRIPTION
    外部コマンド（wsl, chezmoi, docker 等）をラップする関数群。
    Pester テストでモック可能にするため、直接呼び出しを避けて
    これらの関数を経由する。

.NOTES
    テスト時は Mock Invoke-Wsl { ... } のように使用する。
    実際のコマンド実行結果は $LASTEXITCODE で取得可能。
#>

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
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments)]
        [string[]]$Arguments
    )
    & wsl @Arguments
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
    } else {
        if ($MergeStderr) { & chezmoi @Arguments 2>&1 | ForEach-Object { Write-Host $_ } } else { & chezmoi @Arguments }
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
        [string[]]$Arguments
    )
    & winget @Arguments
}

<#
.SYNOPSIS
    diskpart コマンドを実行する（内部関数）
.DESCRIPTION
    cmd /c 経由で diskpart を実行する。モック可能にするためラッパー関数として分離。
#>
function Invoke-DiskpartInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptPath
    )
    # diskpart requires admin privileges.
    # Use Start-Process with -NoNewWindow to avoid output capture issues.
    # Note: Start-Process with -RedirectStandardOutput requires additional privileges.
    $proc = Start-Process -FilePath "diskpart" -ArgumentList "/s", $ScriptPath -Wait -PassThru -NoNewWindow
    return @{
        Output   = $null
        ExitCode = $proc.ExitCode
    }
}

<#
.SYNOPSIS
    diskpart コマンドを実行する
.PARAMETER ScriptContent
    diskpart スクリプトの内容
.OUTPUTS
    コマンドの出力
.EXAMPLE
    Invoke-Diskpart -ScriptContent "list disk"
#>
function Invoke-Diskpart {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptContent
    )
    $tmp = New-TemporaryFile
    try {
        Set-ContentNoNewline -Path $tmp -Value $ScriptContent
        # Run diskpart via internal function (mockable for tests)
        $result = Invoke-DiskpartInternal -ScriptPath $tmp.FullName

        # Output the result
        if ($result.Output) {
            $result.Output | ForEach-Object { Write-Output $_ }
        }

        # Check for errors
        if ($result.ExitCode -ne 0) {
            throw "diskpart failed with exit code $($result.ExitCode)"
        }
    } finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
}

<#
.SYNOPSIS
    ファイルに内容を書き込む（改行なし）
.PARAMETER Path
    書き込み先のパス
.PARAMETER Value
    書き込む内容
#>
function Set-ContentNoNewline {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [string]$Value
    )
    Set-Content -Path $Path -Value $Value -NoNewline
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
    プロセスを安全に取得する
.PARAMETER Name
    プロセス名
.OUTPUTS
    プロセスオブジェクト、存在しない場合は $null
.EXAMPLE
    $proc = Get-ProcessSafe -Name "Docker Desktop"
    if ($proc) { "Docker Desktop is running" }
#>
function Get-ProcessSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )
    Get-Process -Name $Name -ErrorAction SilentlyContinue
}

<#
.SYNOPSIS
    プロセスを安全に停止する
.PARAMETER Name
    プロセス名
.EXAMPLE
    Stop-ProcessSafe -Name "Docker Desktop"
#>
function Stop-ProcessSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )
    Stop-Process -Name $Name -ErrorAction SilentlyContinue
}

<#
.SYNOPSIS
    プロセスを起動する
.PARAMETER FilePath
    実行ファイルのパス
.EXAMPLE
    Start-ProcessSafe -FilePath "C:\Program Files\Docker\Docker\Docker Desktop.exe"
#>
function Start-ProcessSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath
    )
    Start-Process -FilePath $FilePath | Out-Null
}

<#
.SYNOPSIS
    ファイルをコピーする
.PARAMETER Source
    コピー元パス
.PARAMETER Destination
    コピー先パス
.PARAMETER Force
    上書きを許可するか
.EXAMPLE
    Copy-FileSafe -Source ".\source.txt" -Destination ".\dest.txt" -Force
#>
function Copy-FileSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Source,
        [Parameter(Mandatory)]
        [string]$Destination,
        [switch]$Force
    )
    Copy-Item -LiteralPath $Source -Destination $Destination -Force:$Force
}

<#
.SYNOPSIS
    ファイルの内容を取得する
.PARAMETER Path
    ファイルパス
.OUTPUTS
    ファイルの内容
.EXAMPLE
    $content = Get-FileContentSafe -Path ".\config.json"
#>
function Get-FileContentSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    Get-Content -Raw -LiteralPath $Path
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
        [switch]$Directory
    )
    $params = @{
        LiteralPath = $Path
        ErrorAction = 'SilentlyContinue'
    }
    if ($Filter) { $params['Filter'] = $Filter }
    if ($Recurse) { $params['Recurse'] = $true }
    if ($Directory) { $params['Directory'] = $true }
    Get-ChildItem @params
}

<#
.SYNOPSIS
    レジストリ値を取得する
.PARAMETER Path
    レジストリパス
.OUTPUTS
    レジストリキーのプロパティ
.EXAMPLE
    Get-RegistryValue -Path "HKCU:\Software\Microsoft"
#>
function Get-RegistryValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    Get-ItemProperty -Path $Path -ErrorAction SilentlyContinue
}

<#
.SYNOPSIS
    レジストリキーの子キーを取得する
.PARAMETER Path
    レジストリパス
.OUTPUTS
    子キーの配列
.EXAMPLE
    Get-RegistryChildItem -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss"
#>
function Get-RegistryChildItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    Get-ChildItem -Path $Path -ErrorAction SilentlyContinue
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
    npm コマンドを実行する
.PARAMETER Arguments
    npm に渡す引数
.OUTPUTS
    コマンドの出力
.EXAMPLE
    Invoke-Npm -Arguments @("--version")
    Invoke-Npm -Arguments @("install", "-g", "@google/gemini-cli")
#>
function Invoke-Npm {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )
    & npm @Arguments
}

<#
.SYNOPSIS
    pnpm コマンドを実行する
.PARAMETER Arguments
    pnpm に渡す引数
.OUTPUTS
    コマンドの出力
.EXAMPLE
    Invoke-Pnpm -Arguments @("--version")
    Invoke-Pnpm -Arguments @("add", "-g", "@google/gemini-cli")
#>
function Invoke-Pnpm {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )
    & pnpm @Arguments
}

<#
.SYNOPSIS
    docker コマンドを実行する
.PARAMETER Arguments
    docker に渡す引数
.OUTPUTS
    コマンドの出力
.EXAMPLE
    Invoke-Docker "ps" "--filter" "name=openclaw"
    Invoke-Docker "compose" "-f" "path/to/docker-compose.yml" "up" "-d"
#>
function Invoke-Docker {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments)]
        [string[]]$Arguments
    )
    & docker @Arguments
}

<#
.SYNOPSIS
    1Password CLI の account list を実行する
.DESCRIPTION
    Pester でモック可能にするため直接呼び出しを避けてラップする。
    ExitCode を PSCustomObject に含めて返す。
.PARAMETER OpExe
    op.exe のパス
.OUTPUTS
    [PSCustomObject]@{ Output=[string]; ExitCode=[int] }
.EXAMPLE
    $result = Invoke-OpAccountList -OpExe "C:\op.exe"
    if ($result.ExitCode -eq 0) { "signed in" }
#>
function Invoke-OpAccountList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OpExe
    )
    $output = & $OpExe account list 2>&1
    return [PSCustomObject]@{ Output = $output; ExitCode = $LASTEXITCODE }
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
        [string]$Path
    )
    [System.Environment]::SetEnvironmentVariable("PATH", $Path, "User")
}

<#
.SYNOPSIS
    対話環境かどうかを判定する
.DESCRIPTION
    Pester でモック可能にするため [Environment]::UserInteractive / [Console]::IsInputRedirected を
    直接呼ばずにラップする。非対話環境（CI、リダイレクト入力）では $false を返す。
#>
function Test-InteractiveEnvironment {
    return [Environment]::UserInteractive -and -not [Console]::IsInputRedirected
}

