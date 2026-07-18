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

    It 'should fail when a required command is missing' {
        Mock Get-Command {
            if ($Name -eq 'nvim') { return $null }
            return [pscustomobject]@{ Name = $Name; Source = "C:\tools\$Name.exe" }
        }

        { Test-DotfilesEnvironment } | Should -Throw '*Missing command: nvim*'
    }

    It 'should fail when an acceptance command exits nonzero' {
        Mock Invoke-Docker {
            $global:LASTEXITCODE = if ($Arguments -contains 'info') { 1 } else { 0 }
        }

        { Test-DotfilesEnvironment } | Should -Throw '*docker info failed*'
    }

    It 'should run acceptance before printing final completion' {
        $content = Get-Content -LiteralPath $script:installTarget -Raw
        $acceptanceIndex = $content.IndexOf('Test-DotfilesEnvironment -Runtime')
        $completionIndex = $content.IndexOf('Setup Complete!')

        $acceptanceIndex | Should -BeGreaterThan -1
        $completionIndex | Should -BeGreaterThan $acceptanceIndex
    }
}
