<#
.SYNOPSIS
    管理者権限の自動昇格を行う

.DESCRIPTION
    現在のプロセスが管理者権限で実行されていない場合、
    UAC プロンプトを表示して管理者権限で再起動する。

.PARAMETER ScriptPath
    再起動するスクリプトのパス（$PSCommandPath を渡す）

.PARAMETER BoundParameters
    スクリプトに渡されたパラメータ（$PSBoundParameters を渡す）

.EXAMPLE
    # スクリプトの先頭で呼び出す
    . .\lib\Request-AdminElevation.ps1
    Request-AdminElevation -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters
#>

function Test-IsAdmin {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

function Exit-Script {
    [CmdletBinding()]
    param(
        [int]$ExitCode = 0
    )
    exit $ExitCode
}

function Request-AdminElevation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptPath,

        [Parameter(Mandatory)]
        [System.Collections.Generic.Dictionary[string, object]]$BoundParameters
    )

    if (Test-IsAdmin) {
        return
    }

    Write-Host "管理者権限が必要です。UAC プロンプトを表示します..." -ForegroundColor Yellow

    $arguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$ScriptPath`"")

    foreach ($key in $BoundParameters.Keys) {
        $value = $BoundParameters[$key]
        if ($value -is [switch]) {
            if ($value) { $arguments += "-$key" }
        } elseif ($value -is [hashtable]) {
            # Hashtable parameters need special handling
            $hashtableStr = "@{"
            $pairs = @()
            foreach ($hKey in $value.Keys) {
                $hValue = $value[$hKey]
                if ($hValue -is [bool]) {
                    $pairs += "$hKey=`$$hValue"
                } elseif ($hValue -is [string]) {
                    $pairs += "$hKey='$hValue'"
                } else {
                    $pairs += "$hKey=$hValue"
                }
            }
            $hashtableStr += ($pairs -join ";") + "}"
            $arguments += "-$key"
            $arguments += $hashtableStr
        } else {
            $arguments += "-$key"
            $arguments += "`"$value`""
        }
    }

    Start-Process pwsh -ArgumentList $arguments -Verb RunAs
    Exit-Script -ExitCode 0
}
