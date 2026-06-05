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

    It 'should preserve CRLF and UTF-8 no BOM when treefmt formats PowerShell scripts' {
        $treefmtToml = Get-Content -LiteralPath (Join-Path $script:repoRoot ".treefmt.toml") -Raw
        $treefmtNix = Get-Content -LiteralPath (Join-Path $script:repoRoot "nix/flakes/treefmt.nix") -Raw

        foreach ($content in @($treefmtToml, $treefmtNix)) {
            $content | Should -Match '\[string\]\[char\]13 \+ \[string\]\[char\]10'
            $content | Should -Match '\[System\.IO\.File\]::WriteAllText'
            $content | Should -Match '\[System\.Text\.UTF8Encoding\]::new\(\$false\)'
            $content | Should -Not -Match 'Set-Content -LiteralPath \$env:FILENAME'
        }
    }
}
