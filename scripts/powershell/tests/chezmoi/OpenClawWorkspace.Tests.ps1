#Requires -Module Pester

$script:hasChezmoi = $null -ne (Get-Command chezmoi -ErrorAction SilentlyContinue)

BeforeAll {
    $script:repoRoot = Resolve-Path (Join-Path $PSScriptRoot "../../../..")
    $script:chezmoiRoot = Join-Path $script:repoRoot "chezmoi"
    $script:scriptPath = Join-Path $script:chezmoiRoot ".chezmoiscripts/run_after_configure-openclaw-workspace_windows.ps1.tmpl"
    $script:renderOpenClawWorkspaceScript = {
        param(
            [Parameter(Mandatory = $true)]
            [string]$DestinationDirectory,
            [Parameter(Mandatory = $true)]
            [string]$TemplatePath,
            [Parameter(Mandatory = $true)]
            [string]$SourceRoot
        )

        $renderedPath = Join-Path $DestinationDirectory "run_after_configure-openclaw-workspace_windows.ps1"
        $content = Get-Content -LiteralPath $TemplatePath -Raw
        $useChezmoi = $null -ne (Get-Command chezmoi -ErrorAction SilentlyContinue)

        if ($useChezmoi) {
            $output = $content | chezmoi --source $SourceRoot execute-template --init --no-tty 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to render OpenClaw workspace script template: $($output | Out-String)"
            }
            $content = $output -join [Environment]::NewLine
        }

        Set-Content -LiteralPath $renderedPath -Value $content -Encoding UTF8
        return $renderedPath
    }
}

Describe 'OpenClaw workspace chezmoi script' {
    It 'is managed as a chezmoi script' {
        Test-Path -LiteralPath $script:scriptPath -PathType Leaf | Should -BeTrue
        $script:scriptPath | Should -Match '\.ps1\.tmpl$' -Because 'chezmoi-managed PowerShell scripts should be templates, not raw .ps1 files'
    }

    It 'requires an explicit LIFELOG_ROOT and does not search default paths' {
        $content = Get-Content -LiteralPath $script:scriptPath -Raw

        $content | Should -Match 'LIFELOG_ROOT' -Because 'lifelog root must be supplied explicitly'
        $content | Should -Not -Match 'D:\\\\lifelog|D:/lifelog|\.openclaw\\workspace' -Because 'the script must not bake in a candidate root'
        $content | Should -Not -Match 'Get-ChildItem.*lifelog|Resolve-Path.*lifelog' -Because 'the script must not discover lifelog by scanning the filesystem'
    }

    It 'passes LIFELOG_ROOT through chezmoi scriptEnv without a default path' {
        $content = Get-Content -LiteralPath (Join-Path $script:chezmoiRoot ".chezmoi.toml.tmpl") -Raw

        $content | Should -Match 'OPENCLAW_LIFELOG_ROOT_FOR_INIT' -Because 'the setup script needs a no-prompt channel that cannot be masked by an old scriptEnv entry'
        $content | Should -Not -Match 'promptString\s+"LIFELOG_ROOT"' -Because 'CI renders templates without a TTY'
        $content | Should -Match '(?m)^\s*LIFELOG_ROOT\s*=\s*\{\{\s*\$lifelogRoot\s*\|\s*quote\s*\}\}' -Because 'scriptEnv should receive the explicit lifelog root'
        $content | Should -Not -Match 'D:\\\\lifelog|D:/lifelog' -Because 'the source config must not define a default lifelog root'
        $content | Should -Not -Match '(?m)^\s*LIFELOG_ROOT\s*=\s*""' -Because 'an empty active config entry would mask the real environment variable'
    }

    It 'matches only concrete OpenClaw gateway process commands' {
        $content = Get-Content -LiteralPath $script:scriptPath -Raw
        $match = [regex]::Match(
            $content,
            "\`$runsOpenClawGateway\s*=\s*\`$commandLine\s+-match\s+'([^']+)'"
        )
        $match.Success | Should -BeTrue
        $gatewayPattern = $match.Groups[1].Value

        $gatewayPattern | Should -Match 'node_modules'
        @(
            '"C:\Program Files\nodejs\node.exe" C:\Users\rurus\AppData\Roaming\npm\node_modules\openclaw\dist\index.js gateway --port 18789',
            '"C:\Program Files\nodejs\node.exe" "C:\Users\rurus\AppData\Roaming\npm\node_modules\openclaw\openclaw.mjs" gateway --port 18789'
        ) | ForEach-Object {
            $_ | Should -Match $gatewayPattern
        }

        @(
            'kubectl logs -n openclaw deployment/openclaw-gateway -f',
            'pwsh -Command "openclaw gateway diagnostics"'
        ) | ForEach-Object {
            $_ | Should -Not -Match $gatewayPattern
        }
    }

    It 'renders without prompting when LIFELOG_ROOT is missing' -Skip:(-not $script:hasChezmoi) {
        $oldLifelogRoot = $env:LIFELOG_ROOT
        $oldSetupRoot = $env:OPENCLAW_LIFELOG_ROOT_FOR_INIT
        try {
            Remove-Item Env:\LIFELOG_ROOT -ErrorAction SilentlyContinue
            Remove-Item Env:\OPENCLAW_LIFELOG_ROOT_FOR_INIT -ErrorAction SilentlyContinue
            $emptyConfig = Join-Path $TestDrive "empty-chezmoi.toml"
            "" | Set-Content -LiteralPath $emptyConfig -Encoding UTF8

            $result = Get-Content -LiteralPath (Join-Path $script:chezmoiRoot ".chezmoi.toml.tmpl") -Raw |
                chezmoi --config $emptyConfig --source $script:chezmoiRoot execute-template --init --no-tty 2>&1

            $LASTEXITCODE | Should -Be 0
            ($result | Out-String) | Should -Not -Match '(?m)^\s*LIFELOG_ROOT\s*='
        }
        finally {
            if ($null -eq $oldLifelogRoot) {
                Remove-Item Env:\LIFELOG_ROOT -ErrorAction SilentlyContinue
            }
            else {
                $env:LIFELOG_ROOT = $oldLifelogRoot
            }

            if ($null -eq $oldSetupRoot) {
                Remove-Item Env:\OPENCLAW_LIFELOG_ROOT_FOR_INIT -ErrorAction SilentlyContinue
            }
            else {
                $env:OPENCLAW_LIFELOG_ROOT_FOR_INIT = $oldSetupRoot
            }
        }
    }

    It 'renders setup-provided LIFELOG_ROOT without prompting' -Skip:(-not $script:hasChezmoi) {
        $oldLifelogRoot = $env:LIFELOG_ROOT
        $oldSetupRoot = $env:OPENCLAW_LIFELOG_ROOT_FOR_INIT
        try {
            Remove-Item Env:\LIFELOG_ROOT -ErrorAction SilentlyContinue
            $env:OPENCLAW_LIFELOG_ROOT_FOR_INIT = "X:\explicit\lifelog"
            $emptyConfig = Join-Path $TestDrive "empty-chezmoi.toml"
            "" | Set-Content -LiteralPath $emptyConfig -Encoding UTF8

            $result = Get-Content -LiteralPath (Join-Path $script:chezmoiRoot ".chezmoi.toml.tmpl") -Raw |
                chezmoi --config $emptyConfig --source $script:chezmoiRoot execute-template --init --no-tty 2>&1

            $LASTEXITCODE | Should -Be 0
            ($result | Out-String) | Should -Match 'LIFELOG_ROOT = "X:\\\\explicit\\\\lifelog"'
        }
        finally {
            if ($null -eq $oldLifelogRoot) {
                Remove-Item Env:\LIFELOG_ROOT -ErrorAction SilentlyContinue
            }
            else {
                $env:LIFELOG_ROOT = $oldLifelogRoot
            }

            if ($null -eq $oldSetupRoot) {
                Remove-Item Env:\OPENCLAW_LIFELOG_ROOT_FOR_INIT -ErrorAction SilentlyContinue
            }
            else {
                $env:OPENCLAW_LIFELOG_ROOT_FOR_INIT = $oldSetupRoot
            }
        }
    }

    It 'fails when LIFELOG_ROOT is missing' {
        $oldLifelogRoot = $env:LIFELOG_ROOT
        $oldOpenClawConfig = $env:OPENCLAW_CONFIG
        try {
            Remove-Item Env:\LIFELOG_ROOT -ErrorAction SilentlyContinue
            $env:OPENCLAW_CONFIG = Join-Path $TestDrive "openclaw.json"
            $renderedScriptPath = & $script:renderOpenClawWorkspaceScript -DestinationDirectory $TestDrive -TemplatePath $script:scriptPath -SourceRoot $script:chezmoiRoot

            $result = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $renderedScriptPath 2>&1
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

    It 'should not manage OpenClaw secrets or pairing tokens' {
        $content = Get-Content -LiteralPath $script:scriptPath -Raw

        $content | Should -Not -Match 'op://|onepasswordRead|op\s+read' -Because 'OpenClaw config patching must not resolve or write secrets'
        $content | Should -Not -Match 'gateway\.auth\.token|OPENCLAW_GATEWAY_TOKEN|apiKey|botToken|appToken' -Because 'tokens and API keys must stay in local OpenClaw state or 1Password'
        $content | Should -Match 'scope upgrade' -Because 'device pairing scope upgrades remain an explicit per-device approval step'
    }

    It 'should write agents.defaults.workspace and enable browser while preserving existing config values' {
        $oldLifelogRoot = $env:LIFELOG_ROOT
        $oldOpenClawConfig = $env:OPENCLAW_CONFIG
        $oldGatewayRestartCommand = $env:OPENCLAW_GATEWAY_RESTART_COMMAND
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
                browser = @{
                    defaultProfile = "openclaw"
                    profiles = @{
                        openclaw = @{
                            cdpPort = 18800
                            color = "#FF4500"
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
            $restartLogPath = Join-Path $TestDrive "gateway-restart.log"
            $restartCommandPath = Join-Path $TestDrive "restart-gateway.cmd"
            Set-Content -LiteralPath $restartCommandPath -Value @(
                "@echo off"
                "echo restarted>%restartLogPath%"
            ) -Encoding ASCII
            $env:OPENCLAW_GATEWAY_RESTART_COMMAND = $restartCommandPath
            $env:restartLogPath = $restartLogPath
            $renderedScriptPath = & $script:renderOpenClawWorkspaceScript -DestinationDirectory $TestDrive -TemplatePath $script:scriptPath -SourceRoot $script:chezmoiRoot

            & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $renderedScriptPath | Out-Null
            $LASTEXITCODE | Should -Be 0

            $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
            $config.agents.defaults.workspace | Should -Be ([System.IO.Path]::GetFullPath($lifelogRoot).TrimEnd("\"))
            $config.agents.defaults.model.primary | Should -Be "openai/gpt-5.5"
            $config.browser.enabled | Should -BeTrue
            $config.browser.defaultProfile | Should -Be "openclaw"
            $config.browser.profiles.openclaw.cdpPort | Should -Be 18800
            $config.gateway.auth.token | Should -Be "preserve-me"
            Get-Content -LiteralPath $restartLogPath -Raw | Should -Match 'restarted'
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

            if ($null -eq $oldGatewayRestartCommand) {
                Remove-Item Env:\OPENCLAW_GATEWAY_RESTART_COMMAND -ErrorAction SilentlyContinue
            }
            else {
                $env:OPENCLAW_GATEWAY_RESTART_COMMAND = $oldGatewayRestartCommand
            }

            Remove-Item Env:\restartLogPath -ErrorAction SilentlyContinue
        }
    }

    It 'fails when OpenClaw gateway restart fails' {
        $oldLifelogRoot = $env:LIFELOG_ROOT
        $oldOpenClawConfig = $env:OPENCLAW_CONFIG
        $oldGatewayRestartCommand = $env:OPENCLAW_GATEWAY_RESTART_COMMAND
        try {
            $lifelogRoot = Join-Path $TestDrive "custom-lifelog"
            New-Item -ItemType Directory -Path $lifelogRoot -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $lifelogRoot "AGENTS.md") -Value "# lifelog" -Encoding UTF8

            $configPath = Join-Path $TestDrive ".openclaw/openclaw.json"
            New-Item -ItemType Directory -Path (Split-Path -Parent $configPath) -Force | Out-Null
            "{}" | Set-Content -LiteralPath $configPath -Encoding UTF8

            $restartCommandPath = Join-Path $TestDrive "restart-gateway-fail.cmd"
            Set-Content -LiteralPath $restartCommandPath -Value @(
                "@echo off"
                "echo restart failed"
                "exit /b 42"
            ) -Encoding ASCII

            $env:LIFELOG_ROOT = $lifelogRoot
            $env:OPENCLAW_CONFIG = $configPath
            $env:OPENCLAW_GATEWAY_RESTART_COMMAND = $restartCommandPath
            $renderedScriptPath = & $script:renderOpenClawWorkspaceScript -DestinationDirectory $TestDrive -TemplatePath $script:scriptPath -SourceRoot $script:chezmoiRoot

            $result = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $renderedScriptPath 2>&1
            $LASTEXITCODE | Should -Not -Be 0
            ($result | Out-String) | Should -Match 'OpenClaw gateway restart'
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

            if ($null -eq $oldGatewayRestartCommand) {
                Remove-Item Env:\OPENCLAW_GATEWAY_RESTART_COMMAND -ErrorAction SilentlyContinue
            }
            else {
                $env:OPENCLAW_GATEWAY_RESTART_COMMAND = $oldGatewayRestartCommand
            }
        }
    }
}
