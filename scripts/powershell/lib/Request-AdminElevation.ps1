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

    Write-Host "Administrator privileges are required. Showing UAC prompt..." -ForegroundColor Yellow

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

    $elevatedShell = if (Get-Command pwsh -ErrorAction SilentlyContinue) {
        "pwsh"
    } else {
        "powershell.exe"
    }

    try {
        $proc = Start-Process $elevatedShell -ArgumentList $arguments -Verb RunAs -PassThru -Wait
        $exitCode = if ($null -ne $proc -and $null -ne $proc.ExitCode) {
            [int]$proc.ExitCode
        } else {
            1
        }
        Exit-Script -ExitCode $exitCode
    } catch {
        if ($_.Exception -is [System.ComponentModel.Win32Exception] -and $_.Exception.NativeErrorCode -eq 1223) {
            Write-Error "UAC prompt was canceled. Setup did not start."
        } else {
            Write-Error "Failed to start elevated process: $($_.Exception.Message)"
        }
        Exit-Script -ExitCode 1
    }
}
