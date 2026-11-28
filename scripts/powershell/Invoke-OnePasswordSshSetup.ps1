[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$agent = Get-Service -Name ssh-agent -ErrorAction SilentlyContinue
if (-not $agent -or ($agent.Status -eq 'Stopped' -and $agent.StartType -eq 'Disabled')) { return }

$command = @'
$ErrorActionPreference = 'Stop'
try {
    Stop-Service -Name ssh-agent -ErrorAction Stop
    Set-Service -Name ssh-agent -StartupType Disabled -ErrorAction Stop
}
catch { Write-Error $_; exit 1 }
'@
$encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
Write-Host 'Disabling the Windows OpenSSH agent for 1Password; approve the UAC prompt.'
$process = Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList @(
    '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encoded
) -Verb RunAs -PassThru
try {
    if (-not $process.WaitForExit(120000)) { throw 'Timed out disabling the Windows OpenSSH agent.' }
    if ($process.ExitCode -ne 0) { throw "Disabling the Windows OpenSSH agent failed (exit=$($process.ExitCode))." }
}
finally { $process.Dispose() }

$agent = Get-Service -Name ssh-agent -ErrorAction Stop
if ($agent.Status -ne 'Stopped' -or $agent.StartType -ne 'Disabled') {
    throw 'The Windows OpenSSH agent is still running or enabled.'
}
