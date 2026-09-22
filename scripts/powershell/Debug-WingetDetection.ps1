# IsPackageInstalled の昇格動作診断スクリプト
# 絶対パスに出力（昇格時も確実に書き込める）
$outFile = "D:\ruru\dotfiles\winget_diag_result.txt"
$results = @()
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
$results += "=== IsAdmin: $isAdmin ==="
$results += "=== TEMP: $env:TEMP | User: $env:USERNAME ==="
$results += ""

# Invoke-Winget 関数を定義（Handler と同じ実装）
function Invoke-Winget {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Arguments)
    & winget @Arguments
}

# 関数経由でよぶクラス（IsPackageInstalled と同じロジック）
class WingetChecker {
    # [bool] ではなく [string] で返す（変換による誤魔化しを防ぐ）
    [string] IsInstalledViaFunc([string]$packageId) {
        $output = Invoke-Winget -Arguments @("list", "--id", $packageId, "--exact", "--accept-source-agreements")
        $ec = $LASTEXITCODE
        $matched = [bool]($output | Where-Object { $_ -match [regex]::Escape($packageId) })
        # Handler.Winget.ps1 の IsPackageInstalled と同じ判定ロジック
        $result = if ($ec -ne 0) { "false(ec!=0)" } elseif ($matched) { "TRUE(matched!)" } else { "false(no-match)" }
        # 出力内容も記録（ASCII変換してパッケージIDが含まれているか確認）
        $sample = ($output | ForEach-Object { $_ -replace '[^\x20-\x7E]', '?' } | Select-Object -Last 2) -join ' || '
        return "func|ec=$ec|matched=$matched|lines=$($output.Count)|result=$result|sample=[$sample]"
    }
    [string] IsInstalledDirect([string]$packageId) {
        $output = & winget list --id $packageId --exact --accept-source-agreements 2>&1
        $ec = $LASTEXITCODE
        $matched = [bool]($output | Where-Object { $_ -match [regex]::Escape($packageId) })
        return "direct|ec=$ec|matched=$matched|lines=$($output.Count)|result=$(if ($ec -ne 0) {'false(ec)'} elseif ($matched) {'true'} else {'false'})"
    }
}

$checker = [WingetChecker]::new()
$testIds = @("AgileBits.1Password", "Anysphere.Cursor", "OpenAI.Codex", "ZedIndustries.Zed", "Task.Task")

foreach ($packageId in $testIds) {
    $results += "=== $packageId ==="

    # 方法1: 関数経由 (Handler.Winget.ps1 と同じ)
    $r1 = $checker.IsInstalledViaFunc($packageId)
    $results += "  $r1"

    # 方法2: クラス内で直接 & winget
    $r2 = $checker.IsInstalledDirect($packageId)
    $results += "  $r2"

    # 方法3: スクリプトスコープで直接
    $out3 = & winget list --id $packageId --exact --accept-source-agreements 2>&1
    $ec3 = $LASTEXITCODE
    $matched3 = [bool]($out3 | Where-Object { $_ -match [regex]::Escape($packageId) })
    $ascii3 = ($out3 | ForEach-Object { $_ -replace '[^\x20-\x7E]', '?' } | Select-Object -Last 2) -join ' | '
    $results += "  script|ec=$ec3|matched=$matched3|lines=$($out3.Count)|lastline=[$ascii3]"
    $results += ""
}

$results | Set-Content -Path $outFile -Encoding UTF8 -Force
Write-Host "診断完了: $outFile"
