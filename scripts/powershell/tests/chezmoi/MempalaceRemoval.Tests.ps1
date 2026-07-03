#Requires -Module Pester

BeforeAll {
    $script:repoRoot = Resolve-Path (Join-Path $PSScriptRoot "../../../..")
    $script:chezmoiRoot = Join-Path $script:repoRoot "chezmoi"
}

Describe 'mempalace is not installed by chezmoi' {
    It 'does not include mempalace deploy scripts' {
        $deployScripts = Get-ChildItem -Path (Join-Path $script:chezmoiRoot ".chezmoiscripts") -Recurse -File |
            Where-Object { $_.Name -match 'mempalace' }

        $deployScripts | Should -BeNullOrEmpty -Because "mempalace init prompts interactively and can hang chezmoi apply"
    }

    It 'does not configure the mempalace MCP server' {
        $paths = @(
            (Join-Path $script:chezmoiRoot ".chezmoidata/mcp_servers.yaml"),
            (Join-Path $script:repoRoot ".codex/config.toml"),
            (Join-Path $script:repoRoot ".mcp.json")
        )

        foreach ($path in $paths) {
            $content = Get-Content -Path $path -Raw
            $content | Should -Not -Match 'mempalace-mcp'
            $content | Should -Not -Match '(?m)^\s*(\[mcp_servers\.mempalace\]|"mempalace"\s*:|- name:\s*mempalace)\s*$'
        }
    }

    It 'does not run mempalace installation or initialization commands' {
        $files = Get-ChildItem -Path $script:chezmoiRoot -Recurse -File |
            Where-Object { $_.FullName -notmatch '\\.git\\' }

        $violations = @()
        foreach ($file in $files) {
            $content = Get-Content -Path $file.FullName -Raw -ErrorAction SilentlyContinue
            if (-not $content) { continue }

            if ($content -match 'uv\s+tool\s+install\s+mempalace|mempalace\s+init') {
                $violations += $file.FullName
            }
        }

        $violations | Should -BeNullOrEmpty -Because "chezmoi apply must not invoke interactive mempalace setup"
    }
}

Describe 'serena is not installed by chezmoi' {
    It 'does not configure the serena MCP server' {
        $paths = @(
            (Join-Path $script:chezmoiRoot ".chezmoidata/mcp_servers.yaml"),
            (Join-Path $script:repoRoot ".codex/config.toml"),
            (Join-Path $script:repoRoot ".mcp.json")
        )

        foreach ($path in $paths) {
            if (-not (Test-Path -LiteralPath $path)) { continue }

            $content = Get-Content -LiteralPath $path -Raw
            $content | Should -Not -Match '(?i)serena-mcp-server|oraios/serena'
            $content | Should -Not -Match '(?im)^\s*(\[mcp_servers\.serena\]|"serena"\s*:|- name:\s*serena)\s*$'
        }
    }

    It 'does not run serena installation or initialization commands' {
        $files = Get-ChildItem -Path $script:chezmoiRoot -Recurse -File |
            Where-Object { $_.FullName -notmatch '\\.git\\' }

        $violations = @()
        foreach ($file in $files) {
            $content = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
            if (-not $content) { continue }

            if ($content -match '(?i)(uvx|uv\s+tool\s+install|pipx|pip\s+install).*serena|serena-mcp-server|oraios/serena') {
                $violations += $file.FullName
            }
        }

        $violations | Should -BeNullOrEmpty -Because "chezmoi apply must not install or configure Serena"
    }
}
