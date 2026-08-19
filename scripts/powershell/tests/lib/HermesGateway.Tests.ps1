#Requires -Module Pester

BeforeAll {
    function Invoke-Docker {
        param([string[]]$Arguments)
        throw "Unexpected Docker invocation: $($Arguments -join ' ')"
    }

    . $PSScriptRoot/../../lib/HermesGateway.ps1
}

Describe 'Hermes Gateway convergence adapter' {
    BeforeEach {
        $script:dockerArguments = @()
        $global:LASTEXITCODE = 0
    }

    It 'executes the in-container convergence command with the exact Compose arguments' {
        Mock Invoke-Docker {
            $script:dockerArguments = @($Arguments)
            $global:LASTEXITCODE = 0
            return 'converged'
        }

        $result = Invoke-HermesGatewayConvergence -ComposeFile 'C:\dotfiles\compose.yml'

        $result | Should -BeNullOrEmpty
        $script:dockerArguments | Should -Be @(
            'compose', '-f', 'C:\dotfiles\compose.yml',
            'exec', '-T', 'hermes', '/usr/local/bin/hermes-gateway-converge'
        )
    }

    It 'throws a sanitized InvalidOperationException when Docker exits nonzero' {
        $secret = 'secret-token'
        Mock Invoke-Docker {
            $script:dockerArguments = @($Arguments)
            $global:LASTEXITCODE = 42
            return "convergence failed with $secret"
        }

        $caught = $null
        try {
            Invoke-HermesGatewayConvergence -ComposeFile 'C:\dotfiles\compose.yml'
        }
        catch {
            $caught = $_.Exception
        }

        $caught | Should -BeOfType ([System.InvalidOperationException])
        $caught.Message | Should -Be 'Hermes profile Gateway convergence failed with exit code 42.'
        $caught.Message | Should -Not -Match ([regex]::Escape($secret))
    }
}
