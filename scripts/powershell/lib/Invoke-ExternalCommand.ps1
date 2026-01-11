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
        [string]$ExePath
    )
    if ($ExePath) {
        & $ExePath @Arguments
    } else {
        & chezmoi @Arguments
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
        & diskpart /s $tmp
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
