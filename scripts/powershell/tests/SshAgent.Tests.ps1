BeforeAll {
    $script:adapter = Join-Path $PSScriptRoot '../Invoke-OnePasswordSshSetup.ps1'
    function Get-Service { [CmdletBinding()] param($Name) }
    function Stop-Service { [CmdletBinding()] param($Name) }
    function Set-Service { [CmdletBinding()] param($Name, $StartupType) }
}

Describe 'Windows SSH agent ownership' {
    BeforeEach {
        $global:DotfilesTestSshAgent = [pscustomobject]@{ Status = 'Running'; StartType = 'Automatic' }
        Mock Get-Service { $global:DotfilesTestSshAgent }
        Mock Stop-Service { $global:DotfilesTestSshAgent.Status = 'Stopped' }
        Mock Set-Service { $global:DotfilesTestSshAgent.StartType = $StartupType }
        Mock Start-Process {
            $encoded = $ArgumentList[-1]
            & ([scriptblock]::Create([Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($encoded))))
            $process = [pscustomobject]@{ ExitCode = 0 }
            $process | Add-Member ScriptMethod WaitForExit { param($Timeout) return $true }
            $process | Add-Member ScriptMethod Dispose { }
            $process
        }
    }

    It 'stops and disables the competing service and leaves it disabled on reapply' {
        & $script:adapter
        $global:DotfilesTestSshAgent.Status | Should -Be 'Stopped'
        $global:DotfilesTestSshAgent.StartType | Should -Be 'Disabled'
        & $script:adapter
        Should -Invoke Start-Process -Times 1 -ParameterFilter { $Verb -eq 'RunAs' }
    }

    It 'propagates refused elevation' {
        Mock Start-Process { throw 'UAC declined' }
        { & $script:adapter } | Should -Throw '*UAC declined*'
        $global:DotfilesTestSshAgent.Status | Should -Be 'Running'
    }

    AfterAll { Remove-Variable -Name DotfilesTestSshAgent -Scope Global }
}
