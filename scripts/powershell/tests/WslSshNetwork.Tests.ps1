BeforeAll {
    . (Join-Path $PSScriptRoot '../lib/Sync-WslSshNetwork.ps1')
    function Invoke-Wsl { param($TimeoutSeconds, $Arguments) }
    function Invoke-NativeCommand { param($Command, $Arguments) }
    function Get-Service { [CmdletBinding()] param($Name) }
    function Start-Service { [CmdletBinding()] param($Name) }
    function Get-NetFirewallRule { [CmdletBinding()] param($PolicyStore, $Name) }
    function Get-NetFirewallPortFilter { param($AssociatedNetFirewallRule) }
    function Get-NetFirewallAddressFilter { param($AssociatedNetFirewallRule) }
    function Remove-NetFirewallRule { [CmdletBinding()] param([Parameter(ValueFromPipeline)]$InputObject) process { } }
    function New-NetFirewallRule {
        param($PolicyStore, $Name, $DisplayName, $Direction, $Action, $Protocol, $LocalPort, $RemoteAddress, $Profile)
    }
}

Describe 'WSL SSH network configuration' {
    BeforeEach {
        Mock Invoke-Wsl { $global:LASTEXITCODE = 0; '2: eth0 inet 172.23.206.4/20 scope global eth0' }
        Mock Invoke-NativeCommand { $global:LASTEXITCODE = 0 }
        Mock Start-Service { }
        Mock Get-Service { [pscustomobject]@{ Status = 'Running' } }
        Mock Get-ItemPropertyValue { '172.23.206.4/22' }
        Mock Get-NetFirewallRule {
            [pscustomobject]@{ Enabled = 'True'; Direction = 'Inbound'; Action = 'Allow'; Profile = 'Any' }
        }
        Mock Get-NetFirewallPortFilter { [pscustomobject]@{ Protocol = 'TCP'; LocalPort = '2222' } }
        Mock Get-NetFirewallAddressFilter {
            [pscustomobject]@{ RemoteAddress = 'LocalSubnet'; LocalAddress = 'Any' }
        }
        Mock Remove-NetFirewallRule { }
        Mock New-NetFirewallRule { }
        Mock Start-Process {
            $process = [pscustomobject]@{ ExitCode = 0 }
            $process | Add-Member ScriptMethod WaitForExit { param($Timeout) return $true }
            $process | Add-Member ScriptMethod Dispose { }
            return $process
        }
    }

    It 'keeps an already restricted rule without requesting elevation' {
        Sync-WslSshNetwork -DistroName NixOS
        Should -Invoke Start-Process -Times 0
    }

    It 'elevates when forwarding configuration or its service has drifted' -ForEach @(
        @{ Drift = 'address' }, @{ Drift = 'firewall' }, @{ Drift = 'service' }
    ) {
        if ($Drift -eq 'address') { Mock Get-ItemPropertyValue { '172.23.100.4/22' } }
        elseif ($Drift -eq 'firewall') { Mock Get-NetFirewallAddressFilter { [pscustomobject]@{ RemoteAddress = @('Any'); LocalAddress = @('Any') } } }
        else { Mock Get-Service { [pscustomobject]@{ Status = 'Stopped' } } }
        Sync-WslSshNetwork -DistroName WorkNix
        Should -Invoke Invoke-Wsl -Times 1 -ParameterFilter { $Arguments -contains 'WorkNix' }
        Should -Invoke Start-Process -Times 1 -ParameterFilter {
            $Verb -eq 'RunAs' -and $ArgumentList -contains '-EncodedCommand'
        }
    }

    It 'applies only the SSH port and a LocalSubnet firewall rule across network profiles' {
        Set-WslSshNetwork -Address 172.23.206.4
        Should -Invoke Invoke-NativeCommand -Times 1 -ParameterFilter {
            [IO.Path]::GetFileName($Command) -eq 'netsh.exe' -and $Arguments -contains 'connectaddress=172.23.206.4' -and
            $Arguments -contains 'listenport=2222' -and $Arguments -contains 'connectport=22'
        }
        Should -Invoke Start-Service -Times 1 -ParameterFilter { $Name -eq 'iphlpsvc' }
        Should -Invoke New-NetFirewallRule -Times 1 -ParameterFilter {
            $Profile -eq 'Any' -and $RemoteAddress -eq 'LocalSubnet' -and
            $Protocol -eq 'TCP' -and $LocalPort -eq 2222 -and $Direction -eq 'Inbound' -and $Action -eq 'Allow'
        }
    }

    It 'propagates declined or failed elevation instead of reporting success' {
        Mock Get-ItemPropertyValue { $null }
        Mock Start-Process { throw 'UAC declined' }
        { Sync-WslSshNetwork } | Should -Throw '*UAC declined*'
    }
}
