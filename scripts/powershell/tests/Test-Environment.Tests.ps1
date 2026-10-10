#Requires -Module Pester

BeforeAll {
    $script:target = Join-Path (Split-Path -Parent $PSScriptRoot) "Test-Environment.ps1"
    $script:installTarget = Join-Path (Split-Path -Parent $PSScriptRoot) "install.ps1"
    . $PSScriptRoot/../lib/Invoke-ExternalCommand.ps1
    . $script:target
}

Describe 'Test-DotfilesEnvironment' {
    BeforeEach {
        $script:dockerCalls = @()
        $script:chezmoiCalls = @()
        $script:wslCalls = @()
        $script:commandLookups = @()

        Mock Get-Command {
            $script:commandLookups += $Name
            return [pscustomobject]@{ Name = $Name; Source = "C:\tools\$Name.exe" }
        }
        Mock Invoke-Docker {
            $script:dockerCalls += , @($Arguments)
            $global:LASTEXITCODE = 0
        }
        Mock Invoke-Chezmoi {
            $script:chezmoiCalls += , @($Arguments)
            $global:LASTEXITCODE = 0
        }
        Mock Invoke-Wsl {
            $script:wslCalls += , @($Arguments)
            $global:LASTEXITCODE = 0
        }
    }

    It 'should run Docker chezmoi and WSL acceptance checks' {
        $result = Test-DotfilesEnvironment -Runtime

        $result.Success | Should -BeTrue
        ($script:dockerCalls | ForEach-Object { $_ -join ' ' }) | Should -Contain 'info'
        ($script:dockerCalls | ForEach-Object { $_ -join ' ' }) | Should -Contain 'compose version'
        ($script:dockerCalls | ForEach-Object { $_ -join ' ' }) | Should -Contain 'run --rm hello-world'
        ($script:chezmoiCalls | ForEach-Object { $_ -join ' ' }) | Should -Contain 'apply --dry-run'
        ($script:wslCalls | ForEach-Object { $_ -join ' ' }) | Should -Contain '--status'
    }

    It 'should verify managed uv instead of an unmanaged Python command' {
        Test-DotfilesEnvironment

        $script:commandLookups | Should -Contain 'uv'
        $script:commandLookups | Should -Not -Contain 'python'
    }

    It 'should skip Docker requirements for the core-only profile' {
        $result = Test-DotfilesEnvironment

        $result.Success | Should -BeTrue
        $script:commandLookups | Should -Not -Contain 'docker'
        $script:dockerCalls.Count | Should -Be 0
        ($script:chezmoiCalls | ForEach-Object { $_ -join ' ' }) | Should -Contain 'apply --dry-run'
        ($script:wslCalls | ForEach-Object { $_ -join ' ' }) | Should -Contain '--status'
    }

    It 'should fail when a required command is missing' {
        Mock Get-Command {
            if ($Name -eq 'nvim') { return $null }
            return [pscustomobject]@{ Name = $Name; Source = "C:\tools\$Name.exe" }
        }

        { Test-DotfilesEnvironment } | Should -Throw '*Missing command: nvim*'
    }

    It 'should verify native Hermes in the configured NixOS distro without Windows Hermes or Docker' {
        $result = Test-DotfilesEnvironment -DistroName 'CustomNixOS'

        $result.Success | Should -BeTrue
        $script:commandLookups | Should -Not -Contain 'hermes'
        $script:commandLookups | Should -Not -Contain 'docker'
        $script:dockerCalls.Count | Should -Be 0
        ($script:wslCalls | ForEach-Object { $_ -join ' ' }) | Should -Contain '--status'
        ($script:wslCalls | Where-Object { $_ -contains 'CustomNixOS' } | ForEach-Object { $_ -join ' ' }) | Should -Match 'test -e /etc/NIXOS.*command -v hermes.*hermes-agent.service'
    }

    It 'should reject completion if NixOS or its native Hermes service is unavailable' {
        Mock Invoke-Wsl {
            $global:LASTEXITCODE = if ($Arguments -contains '-d') { 3 } else { 0 }
        }

        { Test-DotfilesEnvironment -DistroName 'NixOS' } | Should -Throw '*NixOS WSL native Hermes acceptance*'
        $script:dockerCalls.Count | Should -Be 0
    }

    It 'should fail when an acceptance command exits nonzero' {
        Mock Invoke-Docker {
            $global:LASTEXITCODE = if ($Arguments -contains 'info') { 1 } else { 0 }
        }

        { Test-DotfilesEnvironment -Docker } | Should -Throw '*docker info failed*'
    }

    It 'should keep CLI environment acceptance outside GUI-only setup' {
        $content = Get-Content -LiteralPath $script:installTarget -Raw
        $content | Should -Not -Match 'Test-Environment|Test-DotfilesEnvironment|EnableDockerDesktopIntegration'
        $content | Should -Match 'Setup Complete!'
    }
}
