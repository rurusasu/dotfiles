#Requires -Module Pester

BeforeAll {
    $script:repoRoot = Resolve-Path (Join-Path $PSScriptRoot "../../../..")
    $script:chezmoiRoot = Join-Path $script:repoRoot "chezmoi"
    $script:mcpDataPath = Join-Path $script:chezmoiRoot ".chezmoidata/mcp_servers.yaml"
    $script:mcpData = Get-Content -LiteralPath $script:mcpDataPath -Raw

    $script:toolkitServers = @(
        "context7",
        "deepwiki",
        "exa",
        "firecrawl",
        "github-official",
        "obsidian",
        "playwright",
        "tavily"
    )

    $script:toolkitClients = @(
        "codex",
        "cursor",
        "gemini"
    )

    $script:removedServers = @(
        "linear",
        "sentry",
        "cloud-run",
        "superlocalmemory",
        "qmd"
    )

    $script:clientTemplates = @(
        "dot_codex/config.toml.tmpl",
        "dot_cursor/cli-config.json.tmpl",
        "dot_gemini/settings.json.tmpl",
        "dot_codeium/windsurf/mcp_config.json.tmpl"
    ) | ForEach-Object { Join-Path $script:chezmoiRoot $_ }
}

Describe 'Docker MCP Toolkit shared profile' {
    It 'declares the dotfiles profile and every catalog-managed server' {
        $script:mcpData | Should -Match '(?m)^  profile:\s*dotfiles\s*$'

        foreach ($server in $script:toolkitServers) {
            $script:mcpData | Should -Match ([regex]::Escape("catalog://mcp/docker-mcp-catalog/$server"))
        }
    }

    It 'removes the requested unused MCP servers from direct data' {
        foreach ($server in $script:removedServers) {
            $script:mcpData | Should -Not -Match "(?m)^\s+- name:\s*$([regex]::Escape($server))\s*$"
        }
    }

    It 'keeps unsupported direct MCP servers available' {
        foreach ($server in @("plane", "drawio", "kaggle")) {
            $script:mcpData | Should -Match "(?m)^\s+- name:\s*$([regex]::Escape($server))\s*$"
        }
    }

    It 'keeps Hindsight as a direct local HTTP server' {
        $script:mcpData | Should -Match '(?m)^\s+- name:\s*hindsight\s*$'
        $script:mcpData | Should -Match 'http://127\.0\.0\.1:8888/mcp/codex-shared/'
        $script:mcpData | Should -Match '(?ms)- name:\s*hindsight.*?supports:\s*\n(?:\s+- \w+\s*\n){4}'
    }
}

Describe 'MCP Docker gateway client templates' {
    It 'emits the dotfiles gateway in every managed client template' {
        $script:mcpData | Should -Match '(?m)^  server_name:\s*MCP_DOCKER\s*$'
        foreach ($path in $script:clientTemplates) {
            Test-Path -LiteralPath $path | Should -BeTrue -Because "$path must exist for every managed client"
            $content = Get-Content -LiteralPath $path -Raw
            $content | Should -Match 'mcp_toolkit\.server_name'
            $content | Should -Match 'mcp'
            $content | Should -Match 'gateway'
            $content | Should -Match 'mcp_toolkit\.profile'
        }
    }

}

Describe 'MCP Toolkit convergence adapters' {
    It 'uses approved singular PowerShell function names' {
        $windowsPath = Join-Path $script:repoRoot 'scripts/powershell/mcp-toolkit.ps1'
        $windows = Get-Content -LiteralPath $windowsPath -Raw

        $windows | Should -Match 'function Get-Profile'
        $windows | Should -Match 'function Sync-Secret'
        $windows | Should -Match 'function Connect-Client'
        $windows | Should -Not -Match 'function Pull-Profile'
        $windows | Should -Not -Match 'function Sync-Secrets'
        $windows | Should -Not -Match 'function Connect-Clients'
    }

    It 'keeps direct Hindsight in the project MCP config' {
        $projectConfig = Get-Content -LiteralPath (Join-Path $script:repoRoot ".mcp.json") -Raw
        $projectConfig | Should -Match '"hindsight"'
        $projectConfig | Should -Match 'http://127\.0\.0\.1:8888/mcp/codex-shared/'
    }

    It 'uses the same profile and catalog refs on Unix and Windows' {
        $unixPath = Join-Path $script:repoRoot "scripts/sh/mcp-toolkit.sh"
        $windowsPath = Join-Path $script:repoRoot "scripts/powershell/mcp-toolkit.ps1"
        Test-Path -LiteralPath $unixPath | Should -BeTrue
        Test-Path -LiteralPath $windowsPath | Should -BeTrue

        $unix = Get-Content -LiteralPath $unixPath -Raw
        $windows = Get-Content -LiteralPath $windowsPath -Raw

        foreach ($content in @($unix, $windows)) {
            $content | Should -Match 'dotfiles'
            foreach ($server in $script:toolkitServers) {
                $content | Should -Match ([regex]::Escape($server))
            }
            foreach ($server in $script:removedServers) {
                $content | Should -Match ([regex]::Escape($server))
            }
            $content | Should -Not -Match '(?i)(api[_-]?key|token)\s*=\s*[A-Za-z0-9_./+:-]{12,}'
        }
    }

    It 'supports configurable GHCR profile push and pull on both platforms' {
        $unixPath = Join-Path $script:repoRoot "scripts/sh/mcp-toolkit.sh"
        $windowsPath = Join-Path $script:repoRoot "scripts/powershell/mcp-toolkit.ps1"
        $unix = Get-Content -LiteralPath $unixPath -Raw
        $windows = Get-Content -LiteralPath $windowsPath -Raw

        foreach ($content in @($unix, $windows)) {
            $content | Should -Match 'MCP_TOOLKIT_PROFILE_REF'
            $content | Should -Match 'ghcr\.io/rurusasu/dotfiles/mcp-profile:latest'
        }

        $unix | Should -Match 'docker mcp profile push "\$profile_id" "\$profile_ref"'
        $unix | Should -Match 'docker mcp profile pull "\$profile_ref"'
        $windows | Should -Match 'profile", "push", \$ProfileId, \$ProfileRef'
        $windows | Should -Match 'profile", "pull", \$ProfileRef'
    }

    It 'exposes push and pull tasks' {
        $taskfile = Get-Content -LiteralPath (Join-Path $script:repoRoot "taskfiles/mcp/taskfile.yml") -Raw
        $taskfile | Should -Match '(?m)^  toolkit:push:\s*$'
        $taskfile | Should -Match '(?m)^  toolkit:pull:\s*$'
        $taskfile | Should -Match 'mcp-toolkit\.sh push'
        $taskfile | Should -Match 'mcp-toolkit\.sh pull'
        $taskfile | Should -Match 'mcp-toolkit\.ps1 -Action Push'
        $taskfile | Should -Match 'mcp-toolkit\.ps1 -Action Pull'
    }

    It 'registers Docker MCP Toolkit clients on both platforms' {
        $unixPath = Join-Path $script:repoRoot "scripts/sh/mcp-toolkit.sh"
        $windowsPath = Join-Path $script:repoRoot "scripts/powershell/mcp-toolkit.ps1"
        $taskfilePath = Join-Path $script:repoRoot "taskfiles/mcp/taskfile.yml"
        $docsPath = Join-Path $script:repoRoot "docs/chezmoi/secrets.md"
        $unix = Get-Content -LiteralPath $unixPath -Raw
        $windows = Get-Content -LiteralPath $windowsPath -Raw
        $taskfile = Get-Content -LiteralPath $taskfilePath -Raw
        $docs = Get-Content -LiteralPath $docsPath -Raw

        foreach ($client in $script:toolkitClients) {
            $unix | Should -Match ([regex]::Escape($client))
            $windows | Should -Match ([regex]::Escape($client))
        }
        $unix | Should -Match 'docker mcp client connect --global --profile "\$profile_id" --quiet'
        $windows | Should -Match 'client", "connect", "--global", "--profile", \$ProfileId, "--quiet"'
        $taskfile | Should -Match '(?m)^  toolkit:clients:\s*$'
        $taskfile | Should -Match 'mcp-toolkit\.sh clients'
        $taskfile | Should -Match 'mcp-toolkit\.ps1 -Action Clients'
        $docs | Should -Match 'task mcp:toolkit:clients'
        $docs | Should -Match 'Windsurf'
    }

    It 'declares openclaw 1Password references for available Toolkit secrets' {
        $expectedRefs = @{
            'exa.api_key'                  = 'op://openclaw/ExaUsedOpenclawPAT/credential'
            'firecrawl.api_key'            = 'op://openclaw/FirecrawlUsedOpenclawPAT/credential'
            'github.personal_access_token' = 'op://openclaw/GitHubUsedOpenClawPAT/credential'
            'tavily.api_token'             = 'op://openclaw/TavilyUsedOpenclawPAT/credential'
        }

        $script:mcpData | Should -Match '(?m)^  secrets:\s*$'
        $script:mcpData | Should -Match 'account:\s*"my\.1password\.com"'
        $script:mcpData | Should -Match 'vault:\s*"openclaw"'
        $script:mcpData | Should -Match 'context7\.api_key'
        $script:mcpData | Should -Match 'obsidian\.api_key'
        foreach ($entry in $expectedRefs.GetEnumerator()) {
            $expectedLine = '{0}: "{1}"' -f $entry.Key, $entry.Value
            $script:mcpData | Should -Match ([regex]::Escape($expectedLine))
        }
        $script:mcpData | Should -Not -Match 'op://Private/'
    }

    It 'injects Toolkit secrets from 1Password without exposing values' {
        $unixPath = Join-Path $script:repoRoot "scripts/sh/mcp-toolkit.sh"
        $windowsPath = Join-Path $script:repoRoot "scripts/powershell/mcp-toolkit.ps1"
        $taskfilePath = Join-Path $script:repoRoot "taskfiles/mcp/taskfile.yml"
        $docsPath = Join-Path $script:repoRoot "docs/chezmoi/secrets.md"

        foreach ($path in @($unixPath, $windowsPath)) {
            $content = Get-Content -LiteralPath $path -Raw
            $content | Should -Match 'docker mcp secret set'
            $content | Should -Match 'op.*read'
            $content | Should -Match 'MCP_TOOLKIT_OP_ACCOUNT'
            $content | Should -Not -Match '(?i)printf.*(api[_-]?key|token).*op://'
        }

        $taskfile = Get-Content -LiteralPath $taskfilePath -Raw
        $taskfile | Should -Match '(?m)^  toolkit:secrets:\s*$'
        $taskfile | Should -Match 'mcp-toolkit\.sh secrets'
        $taskfile | Should -Match 'mcp-toolkit\.ps1 -Action Secrets'

        $docs = Get-Content -LiteralPath $docsPath -Raw
        $docs | Should -Match 'task mcp:toolkit:secrets'
        $docs | Should -Match '1Password'
    }
}
