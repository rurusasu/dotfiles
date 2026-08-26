#Requires -Module Pester

BeforeAll {
    . $PSScriptRoot/../../lib/SetupHandler.ps1
    . $PSScriptRoot/../../handlers/Handler.Hindsight.ps1
}

Describe 'HindsightHandler' {
    BeforeEach {
        $root = Join-Path $TestDrive 'dotfiles'
        $composeDir = Join-Path $root 'docker/hindsight'
        $scriptDir = Join-Path $root 'scripts/powershell'
        New-Item -ItemType Directory -Path $composeDir, $scriptDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $composeDir 'compose.yml') -Value 'services: {}'
        Set-Content -LiteralPath (Join-Path $scriptDir 'hindsight.ps1') -Value 'param($Action, $ComposeFile)'
        $script:ctx = [SetupContext]::new($root)
        $script:handler = [HindsightHandler]::new()
        Mock Get-Command { [PSCustomObject]@{ Name = $Name } }
    }

    It 'is disabled by default' {
        $script:handler.CanApply($script:ctx) | Should -BeFalse
    }

    It 'is enabled by the Docker-derived Hindsight option' {
        $script:ctx.Options['WithHindsight'] = $true
        $script:handler.CanApply($script:ctx) | Should -BeTrue
    }

    It 'runs before Hermes and outside its handler' {
        $script:handler.Order | Should -BeLessThan 56
        $script:handler.Name | Should -Be 'Hindsight'
        $source = Get-Content -LiteralPath $PSScriptRoot/../../handlers/Handler.HermesAgent.ps1 -Raw
        $source | Should -Not -Match 'hindsight\.ps1|docker\\hindsight'
    }
}
