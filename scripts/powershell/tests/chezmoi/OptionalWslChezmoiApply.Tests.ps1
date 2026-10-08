#Requires -Module Pester

BeforeAll {
    $script:repoRoot = Resolve-Path (Join-Path $PSScriptRoot '../../../..')
    $script:applyLibrary = Join-Path $script:repoRoot 'scripts/powershell/lib/OptionalWslChezmoiApply.ps1'
    . $script:applyLibrary
}

Describe 'Optional WSL chezmoi apply' {
    BeforeEach {
        Mock Get-Command {
            [pscustomobject]@{ Source = 'wsl.exe' }
        } -ParameterFilter { $Name -eq 'wsl.exe' }
    }

    It 'should skip the WSL apply when the configured distro is missing' {
        Mock Invoke-WslForChezmoi {
            [pscustomobject]@{
                ExitCode = -1
                Output   = @('No registered distro: Wsl/Service/WSL_E_DISTRO_NOT_FOUND')
            }
        }

        Invoke-OptionalWslChezmoiApply -Distro 'NixOS' | Should -Be 0
        Should -Invoke Invoke-WslForChezmoi -Times 1 -ParameterFilter {
            $Arguments -join ' ' -eq '-d NixOS -- chezmoi apply --force'
        }
    }

    It 'should propagate errors other than a missing distro' {
        Mock Invoke-WslForChezmoi {
            [pscustomobject]@{
                ExitCode = 23
                Output   = @('chezmoi apply failed')
            }
        }

        Invoke-OptionalWslChezmoiApply -Distro 'NixOS' | Should -Be 23
    }

    It 'should complete when the WSL chezmoi apply succeeds' {
        Mock Invoke-WslForChezmoi {
            [pscustomobject]@{
                ExitCode = 0
                Output   = @('applied')
            }
        }

        Invoke-OptionalWslChezmoiApply -Distro 'NixOS' | Should -Be 0
    }

    It 'should skip WSL when wsl.exe is unavailable' {
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'wsl.exe' }
        Mock Invoke-WslForChezmoi { throw 'WSL should not be invoked when the executable is missing' }

        Invoke-OptionalWslChezmoiApply -Distro 'NixOS' | Should -Be 0
        Should -Invoke Invoke-WslForChezmoi -Times 0
    }
}

Describe 'Chezmoi task wiring and 1Password timeout contract' {
    It 'should run the WSL apply and then one Windows batch secret prefetch' {
        $taskfilePath = Join-Path $script:repoRoot 'taskfiles/install/taskfile.yml'
        $taskfile = Get-Content -LiteralPath $taskfilePath -Raw

        $taskfile | Should -Match '(?s)chezmoi:\s+desc:.*?cmds:\s+- cmd: pwsh -NoProfile -File scripts/powershell/Invoke-OptionalWslChezmoiApply\.ps1 -Distro \{\{\.DISTRO\}\}\s+platforms: \[windows\]\s+- cmd: pwsh -NoProfile -File scripts/powershell/Invoke-ChezmoiApplyWithOnePasswordPrefetch\.ps1\s+platforms: \[windows\]'
        $taskfile | Should -Not -Match 'Invoke-ChezmoiOnePasswordSignIn\.ps1'
    }

    It 'should keep every deploy script on the shared 1Password read timeout' {
        $dataPath = Join-Path $script:repoRoot 'chezmoi/.chezmoidata/onepassword.json'
        $data = Get-Content -LiteralPath $dataPath -Raw | ConvertFrom-Json
        $data.op_read_timeout_seconds | Should -BeGreaterOrEqual 180

        $templates = @(
            'chezmoi/.chezmoiscripts/deploy/kaggle/run_always_deploy.ps1.tmpl',
            'chezmoi/.chezmoiscripts/deploy/ssh/run_always_deploy.ps1.tmpl'
        )
        foreach ($relativePath in $templates) {
            $template = Get-Content -LiteralPath (Join-Path $script:repoRoot $relativePath) -Raw
            $template | Should -Match '\{\{\s*\.op_read_timeout_seconds\s*\}\}' -Because $relativePath
        }
    }

    It 'should keep Windows chezmoi apply moving when an optional 1Password read fails' {
        $kagglePath = Join-Path $script:repoRoot 'chezmoi/.chezmoiscripts/deploy/kaggle/run_always_deploy.ps1.tmpl'
        $sshPath = Join-Path $script:repoRoot 'chezmoi/.chezmoiscripts/deploy/ssh/run_always_deploy.ps1.tmpl'
        $kaggle = Get-Content -LiteralPath $kagglePath -Raw
        $ssh = Get-Content -LiteralPath $sshPath -Raw

        $kaggle | Should -Match '\$process\.ExitCode -ne 0'
        $kaggle | Should -Match 'skipping Kaggle API credentials deployment'
        $kaggle | Should -Match '\$process\.WaitForExit\(\$timeoutMs\)'
        $ssh | Should -Match '\$process\.ExitCode -ne 0'
        $ssh | Should -Match 'skipping \$Label'
        $ssh | Should -Match '\$process\.WaitForExit\(\$timeoutMs\)'
    }
}
