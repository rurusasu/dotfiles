#Requires -Module Pester

BeforeAll {
    $script:repoRoot = Resolve-Path (Join-Path $PSScriptRoot '../../../..')
}

Describe 'Chezmoi task wiring and 1Password timeout contract' {
    It 'should apply only Windows with one batch secret prefetch' {
        $taskfilePath = Join-Path $script:repoRoot 'taskfiles/install/taskfile.yml'
        $taskfile = Get-Content -LiteralPath $taskfilePath -Raw

        $taskfile | Should -Match '(?s)chezmoi:\s+desc:.*?platforms: \[windows\].*?Invoke-ChezmoiApplyWithOnePasswordPrefetch\.ps1'
        $taskfile | Should -Not -Match 'Invoke-OptionalWslChezmoiApply|platforms: \[linux, darwin\]'
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
