#Requires -Module Pester

BeforeAll {
    . $PSScriptRoot/../../lib/SetupHandler.ps1
    . $PSScriptRoot/../../lib/Invoke-ExternalCommand.ps1
    . $PSScriptRoot/../../handlers/Handler.NixRebuild.ps1
    . $PSScriptRoot/../../handlers/Handler.HermesAgent.ps1
}

Describe 'HermesAgentHandler Windows-to-NixOS-WSL routing' {
    BeforeEach {
        $script:handler = [HermesAgentHandler]::new()
        $script:ctx = [SetupContext]::new($TestDrive)
        $script:ctx.Options['WithHermes'] = $true
        $script:wslCommandChecks = 0
        $script:wslListCalls = 0
        $script:dockerCalls = 0

        Mock Write-Host { }
        Mock Get-Command {
            $script:wslCommandChecks++
            $null
        } -ParameterFilter { $Name -eq 'wsl' }
        Mock Invoke-Wsl {
            $script:wslListCalls++
            $global:LASTEXITCODE = 0
            return @('NixOS')
        } -ParameterFilter { $Arguments -contains '--list' -and $Arguments -contains '--quiet' }
        Mock Invoke-Docker {
            $script:dockerCalls++
            throw 'The Windows Hermes handler must never invoke Docker.'
        }
    }

    It 'runs after NixRebuild so the completed rebuild marker is available' {
        $handler.Order | Should -BeGreaterThan ([NixRebuildHandler]::new().Order)
        $handler.Name | Should -Be 'HermesAgent'
        $handler.RequiresAdmin | Should -BeFalse
        $handler.Phase | Should -Be 2
    }

    It 'is disabled unless WithHermes is enabled' {
        $ctx.Options.Remove('WithHermes')

        $handler.CanApply($ctx) | Should -BeFalse
        $script:wslCommandChecks | Should -Be 0
    }

    It 'honors SkipHermesAgent without inspecting WSL or Docker' {
        $ctx.Options['SkipHermesAgent'] = $true

        $handler.CanApply($ctx) | Should -BeFalse
        $script:wslCommandChecks | Should -Be 0
        $script:wslListCalls | Should -Be 0
        $script:dockerCalls | Should -Be 0
    }

    It 'delegates to Nix after a successful rebuild and never probes or invokes Docker' {
        $ctx.Options['NixRebuildApplied'] = $true

        $handler.CanApply($ctx) | Should -BeFalse
        $handler.Apply($ctx).Success | Should -BeTrue
        $script:wslCommandChecks | Should -Be 0
        $script:wslListCalls | Should -Be 0
        $script:dockerCalls | Should -Be 0
    }

    It 'fails with the WSL prerequisite and never invokes Docker when WSL is unavailable' {
        { $handler.CanApply($ctx) } | Should -Throw '*WithHermes on Windows requires WSL and the* NixOS distribution*'
        $script:wslListCalls | Should -Be 0
        $script:dockerCalls | Should -Be 0
    }

    It 'fails with the distro prerequisite and never invokes Docker when NixOS WSL is missing' {
        Mock Get-Command { [PSCustomObject]@{ Name = 'wsl' } } -ParameterFilter { $Name -eq 'wsl' }
        Mock Invoke-Wsl {
            $script:wslListCalls++
            $global:LASTEXITCODE = 0
            return @('Ubuntu')
        } -ParameterFilter { $Arguments -contains '--list' -and $Arguments -contains '--quiet' }

        { $handler.CanApply($ctx) } | Should -Throw "*requires the '$($ctx.DistroName)' NixOS WSL distribution*"
        $script:dockerCalls | Should -Be 0
    }

    It 'fails closed without invoking Docker when WSL distribution discovery fails' {
        Mock Get-Command { [PSCustomObject]@{ Name = 'wsl' } } -ParameterFilter { $Name -eq 'wsl' }
        Mock Invoke-Wsl {
            $script:wslListCalls++
            $global:LASTEXITCODE = 1
            return @('WSL failed')
        } -ParameterFilter { $Arguments -contains '--list' -and $Arguments -contains '--quiet' }

        { $handler.CanApply($ctx) } | Should -Throw '*Unable to inspect WSL distributions*refusing to start a Docker Hermes Agent*'
        $script:dockerCalls | Should -Be 0
    }

    It 'fails rather than falling back to Docker when the NixOS distro exists but rebuild did not complete' {
        Mock Get-Command { [PSCustomObject]@{ Name = 'wsl' } } -ParameterFilter { $Name -eq 'wsl' }

        { $handler.CanApply($ctx) } | Should -Throw '*registered, but its Hermes Nix rebuild did not complete*Docker fallback is disabled*'
        $script:wslListCalls | Should -Be 1
        $script:dockerCalls | Should -Be 0
    }

    It 'does not let direct Apply calls start Docker before the Nix rebuild succeeds' {
        $result = $handler.Apply($ctx)

        $result.Success | Should -BeFalse
        $result.Message | Should -Match 'successful NixOS WSL rebuild'
        $script:dockerCalls | Should -Be 0
    }
}
