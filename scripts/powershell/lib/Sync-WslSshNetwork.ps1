# Keep WSL queries under the original user; elevate only the Windows network changes.
function Set-WslSshNetwork {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Net.IPAddress]$Address)

    if ($Address.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {
        throw 'WSL SSH forwarding requires an IPv4 address.'
    }
    $systemDirectory = if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { 'Sysnative' } else { 'System32' }
    $netsh = [IO.Path]::Combine([Environment]::GetFolderPath('Windows'), $systemDirectory, 'netsh.exe')
    Invoke-NativeCommand -Command $netsh -Arguments @(
        'interface', 'portproxy', 'add', 'v4tov4',
        'listenaddress=0.0.0.0', 'listenport=2222', "connectaddress=$Address", 'connectport=22'
    ) | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "WSL SSH port forwarding failed (exit=$LASTEXITCODE)." }
    $forward = Get-ItemPropertyValue -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\PortProxy\v4tov4\tcp' `
        -Name '0.0.0.0/2222' -ErrorAction Stop
    if ($forward -ne "$Address/22") { throw 'WSL SSH port forwarding did not retain the requested address.' }
    Start-Service -Name iphlpsvc -ErrorAction Stop
    Get-NetFirewallRule -PolicyStore PersistentStore -Name Dotfiles-WslSsh -ErrorAction SilentlyContinue |
        Remove-NetFirewallRule -ErrorAction Stop
    New-NetFirewallRule -PolicyStore PersistentStore -Name Dotfiles-WslSsh -DisplayName 'WSL SSH' `
        -Direction Inbound -Action Allow -Protocol TCP -LocalPort 2222 `
        -RemoteAddress LocalSubnet -Profile Any | Out-Null
}

function Sync-WslSshNetwork {
    [CmdletBinding()]
    param([ValidateNotNullOrEmpty()][string]$DistroName = 'NixOS')

    $output = @(Invoke-Wsl -TimeoutSeconds 15 -Arguments @(
            '-d', $DistroName, '--exec', '/run/current-system/sw/bin/ip', '-4', '-o', 'address', 'show', 'dev', 'eth0'
        ))
    if ($LASTEXITCODE -ne 0) { throw "Could not read the WSL IPv4 address (exit=$LASTEXITCODE): $($output -join ' ')" }
    $addresses = @($output | ForEach-Object {
            if ([string]$_ -match '\binet ([0-9.]+)/') { [Net.IPAddress]::Parse($Matches[1]) }
        })
    if ($addresses.Count -ne 1) { throw 'Expected one IPv4 address on the WSL eth0 interface.' }
    $address = $addresses[0]
    $forward = Get-ItemPropertyValue -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\PortProxy\v4tov4\tcp' `
        -Name '0.0.0.0/2222' -ErrorAction SilentlyContinue
    $rule = Get-NetFirewallRule -PolicyStore PersistentStore -Name Dotfiles-WslSsh -ErrorAction SilentlyContinue
    $matchesRule = $false
    if ($rule -and @($rule).Count -eq 1) {
        $port = Get-NetFirewallPortFilter -AssociatedNetFirewallRule $rule
        $scope = Get-NetFirewallAddressFilter -AssociatedNetFirewallRule $rule
        $remoteAddresses = @($scope.RemoteAddress)
        $localAddresses = @($scope.LocalAddress)
        $matchesRule = $rule.Enabled -eq 'True' -and $rule.Direction -eq 'Inbound' -and
        $rule.Action -eq 'Allow' -and $rule.Profile -eq 'Any' -and
        $port.Protocol -in @('TCP', '6') -and [string]$port.LocalPort -eq '2222' -and
        $remoteAddresses.Count -eq 1 -and $remoteAddresses[0] -eq 'LocalSubnet' -and
        $localAddresses.Count -eq 1 -and $localAddresses[0] -eq 'Any'
    }
    $ipHelperRunning = (Get-Service -Name iphlpsvc -ErrorAction Stop).Status -eq 'Running'
    if ($forward -ne "$address/22" -or -not $matchesRule -or -not $ipHelperRunning) {
        $external = (Join-Path $PSScriptRoot 'Invoke-ExternalCommand.ps1').Replace("'", "''")
        $network = $PSCommandPath.Replace("'", "''")
        $command = ". '$external'; . '$network'; Set-WslSshNetwork -Address '$address'"
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes(
                "`$ErrorActionPreference = 'Stop'; try { $command } catch { Write-Error `$_; exit 1 }"
            ))
        Write-Host 'Applying WSL SSH forwarding; approve the Windows UAC prompt.'
        $process = Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList @(
            '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encoded
        ) -Verb RunAs -WindowStyle Hidden -PassThru
        try {
            if (-not $process.WaitForExit(120000)) {
                throw 'Timed out configuring WSL SSH; the elevated operation may still be running.'
            }
            if ($process.ExitCode -ne 0) { throw "WSL SSH setup failed (exit=$($process.ExitCode))." }
        }
        finally { $process.Dispose() }
    }
    Write-Host 'WSL SSH: Windows TCP 2222 -> WSL TCP 22; LocalSubnet only on every network profile.'
}
