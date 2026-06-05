BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
}

Describe 'CI workflow configuration' {
    It 'should install pinned PSScriptAnalyzer before nix fmt runs treefmt powershell formatter' {
        $workflow = Get-Content -LiteralPath (Join-Path $script:repoRoot ".github/workflows/ci-nix.yml") -Raw

        $workflow | Should -Match 'name:\s+Install PSScriptAnalyzer'
        $workflow | Should -Match 'RequiredVersion 1\.22\.0'
        $workflow | Should -Match 'nix fmt -- --fail-on-change'
    }

    It 'should pin PSScriptAnalyzer used by treefmt powershell formatter' {
        $treefmtToml = Get-Content -LiteralPath (Join-Path $script:repoRoot ".treefmt.toml") -Raw
        $treefmtNix = Get-Content -LiteralPath (Join-Path $script:repoRoot "nix/flakes/treefmt.nix") -Raw

        $treefmtToml | Should -Match 'RequiredVersion 1\.22\.0'
        $treefmtToml | Should -Match 'Import-Module PSScriptAnalyzer -RequiredVersion 1\.22\.0'
        $treefmtNix | Should -Match 'RequiredVersion 1\.22\.0'
        $treefmtNix | Should -Match 'Import-Module PSScriptAnalyzer -RequiredVersion 1\.22\.0'
    }

    It 'should harden Windows PSScriptAnalyzer install against cache and gallery issues' {
        $workflow = Get-Content -LiteralPath (Join-Path $script:repoRoot ".github/workflows/ci-powershell.yml") -Raw

        $workflow | Should -Match 'function Invoke-WithRetry'
        $workflow | Should -Match '\$env:PSModulePath = "\$moduleRoot;\$env:PSModulePath"'
        $workflow | Should -Match 'Install-Module -Name PSScriptAnalyzer .* -SkipPublisherCheck'
    }

    It 'should preserve CRLF and UTF-8 no BOM when treefmt formats PowerShell scripts' {
        $treefmtToml = Get-Content -LiteralPath (Join-Path $script:repoRoot ".treefmt.toml") -Raw
        $treefmtNix = Get-Content -LiteralPath (Join-Path $script:repoRoot "nix/flakes/treefmt.nix") -Raw

        foreach ($content in @($treefmtToml, $treefmtNix)) {
            $content | Should -Match '\[string\]\[char\]13 \+ \[string\]\[char\]10'
            $content | Should -Match '\[System\.IO\.File\]::WriteAllText'
            $content | Should -Match '\[System\.Text\.UTF8Encoding\]::new\(\$false\)'
            $content | Should -Match '\$args\.Count -gt 0'
            $content | Should -Match '\$args\[0\]'
            $content | Should -Match '\$normalized -ne \$raw'
            $content | Should -Not -Match 'Set-Content -LiteralPath \$env:FILENAME'
        }
    }

    It 'should run install.cmd in CI with timeout and completion marker checks' {
        $wingetWorkflow = Get-Content -LiteralPath (Join-Path $script:repoRoot ".github/workflows/ci-winget.yml") -Raw

        $wingetWorkflow | Should -Match '& cmd\.exe /d /c install\.cmd'
        $wingetWorkflow | Should -Match 'install\.cmd'
        $wingetWorkflow | Should -Match 'ForEach-Object'
        $wingetWorkflow | Should -Match '\$LASTEXITCODE'
        $wingetWorkflow | Should -Not -Match 'RedirectStandardOutput'
        $wingetWorkflow | Should -Match 'User Phase Complete!'
    }

    It 'should trigger entrypoint tests when install.cmd or bootstrap tests change' {
        $powershellWorkflow = Get-Content -LiteralPath (Join-Path $script:repoRoot ".github/workflows/ci-powershell.yml") -Raw
        $devcontainerWorkflow = Get-Content -LiteralPath (Join-Path $script:repoRoot ".github/workflows/ci-devcontainer.yml") -Raw

        $powershellWorkflow | Should -Match '"install\.cmd"'
        $devcontainerWorkflow | Should -Match '"tests/bash/\*\*"'
    }
}
