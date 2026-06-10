#Requires -Module Pester

BeforeAll {
    $script:repoRoot = Resolve-Path (Join-Path $PSScriptRoot "../../../..")
    $script:chezmoiRoot = Join-Path $script:repoRoot "chezmoi"
    $script:scriptPath = Join-Path $script:chezmoiRoot ".chezmoiscripts/run_after_configure-openclaw-workspace_windows.ps1"
}

Describe 'OpenClaw workspace chezmoi script' {
    It 'is managed as a chezmoi script' {
        Test-Path -LiteralPath $script:scriptPath -PathType Leaf | Should -BeTrue
    }

    It 'requires an explicit LIFELOG_ROOT and does not search default paths' {
        $content = Get-Content -LiteralPath $script:scriptPath -Raw

        $content | Should -Match 'LIFELOG_ROOT' -Because 'lifelog root must be supplied explicitly'
        $content | Should -Not -Match 'D:\\\\lifelog|D:/lifelog|\.openclaw\\workspace' -Because 'the script must not bake in a candidate root'
        $content | Should -Not -Match 'Get-ChildItem.*lifelog|Resolve-Path.*lifelog' -Because 'the script must not discover lifelog by scanning the filesystem'
    }

    It 'passes LIFELOG_ROOT through chezmoi scriptEnv without a default path' {
        $content = Get-Content -LiteralPath (Join-Path $script:chezmoiRoot ".chezmoi.toml.tmpl") -Raw

        $content | Should -Match 'promptString\s+"LIFELOG_ROOT"' -Because 'chezmoi init should persist the explicit lifelog root supplied by the caller'
        $content | Should -Match '(?m)^\s*LIFELOG_ROOT\s*=\s*\{\{\s*\$lifelogRoot\s*\|\s*quote\s*\}\}' -Because 'scriptEnv should receive the explicit lifelog root'
        $content | Should -Not -Match 'D:\\\\lifelog|D:/lifelog' -Because 'the source config must not define a default lifelog root'
        $content | Should -Not -Match '(?m)^\s*LIFELOG_ROOT\s*=\s*""' -Because 'an empty active config entry would mask the real environment variable'
    }

    It 'fails when LIFELOG_ROOT is missing' {
        $oldLifelogRoot = $env:LIFELOG_ROOT
        $oldOpenClawConfig = $env:OPENCLAW_CONFIG
        try {
            Remove-Item Env:\LIFELOG_ROOT -ErrorAction SilentlyContinue
            $env:OPENCLAW_CONFIG = Join-Path $TestDrive "openclaw.json"

            $result = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $script:scriptPath 2>&1
            $LASTEXITCODE | Should -Not -Be 0
            ($result | Out-String) | Should -Match 'LIFELOG_ROOT'
        }
        finally {
            if ($null -eq $oldLifelogRoot) {
                Remove-Item Env:\LIFELOG_ROOT -ErrorAction SilentlyContinue
            }
            else {
                $env:LIFELOG_ROOT = $oldLifelogRoot
            }

            if ($null -eq $oldOpenClawConfig) {
                Remove-Item Env:\OPENCLAW_CONFIG -ErrorAction SilentlyContinue
            }
            else {
                $env:OPENCLAW_CONFIG = $oldOpenClawConfig
            }
        }
    }

    It 'writes agents.defaults.workspace while preserving existing config values' {
        $oldLifelogRoot = $env:LIFELOG_ROOT
        $oldOpenClawConfig = $env:OPENCLAW_CONFIG
        try {
            $lifelogRoot = Join-Path $TestDrive "custom-lifelog"
            New-Item -ItemType Directory -Path $lifelogRoot -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $lifelogRoot "AGENTS.md") -Value "# lifelog" -Encoding UTF8

            $configPath = Join-Path $TestDrive ".openclaw/openclaw.json"
            New-Item -ItemType Directory -Path (Split-Path -Parent $configPath) -Force | Out-Null
            @{
                agents = @{
                    defaults = @{
                        model = @{
                            primary = "openai/gpt-5.5"
                        }
                    }
                }
                gateway = @{
                    port = 18789
                    auth = @{
                        token = "preserve-me"
                    }
                }
            } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $configPath -Encoding UTF8

            $env:LIFELOG_ROOT = $lifelogRoot
            $env:OPENCLAW_CONFIG = $configPath

            & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $script:scriptPath | Out-Null
            $LASTEXITCODE | Should -Be 0

            $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
            $config.agents.defaults.workspace | Should -Be ([System.IO.Path]::GetFullPath($lifelogRoot).TrimEnd("\"))
            $config.agents.defaults.model.primary | Should -Be "openai/gpt-5.5"
            $config.gateway.auth.token | Should -Be "preserve-me"
        }
        finally {
            if ($null -eq $oldLifelogRoot) {
                Remove-Item Env:\LIFELOG_ROOT -ErrorAction SilentlyContinue
            }
            else {
                $env:LIFELOG_ROOT = $oldLifelogRoot
            }

            if ($null -eq $oldOpenClawConfig) {
                Remove-Item Env:\OPENCLAW_CONFIG -ErrorAction SilentlyContinue
            }
            else {
                $env:OPENCLAW_CONFIG = $oldOpenClawConfig
            }
        }
    }
}
