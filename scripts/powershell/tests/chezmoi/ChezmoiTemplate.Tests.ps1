#Requires -Module Pester

<#
.SYNOPSIS
    chezmoi テンプレート (.tmpl) のバリデーションテスト

.DESCRIPTION
    AGENTS.md のルールに基づき、テンプレートの安全性を静的に検証する:
    - onepasswordRead がテンプレート展開中に呼ばれないか
    - 主要テンプレートに必須セクションが含まれているか
#>

BeforeAll {
    $script:repoRoot = Join-Path $PSScriptRoot "../../../.."
    $script:chezmoiRoot = Join-Path $PSScriptRoot "../../../../chezmoi"
    $script:templateFiles = Get-ChildItem -Path $script:chezmoiRoot -Filter "*.tmpl" -Recurse
}

Describe 'chezmoi テンプレート バリデーション' {
    Context 'onepasswordRead はテンプレート展開中に呼ばない' {
        It 'すべての .tmpl ファイルで onepasswordRead を呼ばないこと' {
            $violations = @()

            foreach ($file in $script:templateFiles) {
                $content = Get-Content -Path $file.FullName -Raw -ErrorAction SilentlyContinue
                if (-not $content) { continue }

                if ($content -match '\{\{[^}]*onepasswordRead') {
                    $violations += $file.FullName
                }
            }

            $violations | Should -BeNullOrEmpty -Because (
                "1Password app integration failures must not abort chezmoi template rendering. " +
                "Use non-failing runtime op read instead. Violations: $($violations -join ', ')"
            )
        }

        It 'should not recommend template-time 1Password lookup in secret docs' {
            $secretsDocPath = Join-Path $script:repoRoot "docs/chezmoi/secrets.md"
            $content = Get-Content -LiteralPath $secretsDocPath -Raw

            $content | Should -Not -Match '\{\{\s*onepassword(Read)?\b' -Because 'docs must not recommend template-time 1Password lookups'
            $content | Should -Match 'op read --account' -Because 'docs should describe explicit-account runtime reads'
            $content | Should -Match 'op run --env-file' -Because 'docs should describe the official env-file injection pattern'
            $content | Should -Not -Match 'OpenClaw は local state|openclaw devices|OpenClaw 用 provider API keys' -Because 'OpenClaw is no longer managed by dotfiles'
        }

    }

    Context 'mcp_servers.yaml の op_env は env キーと一致すること' {
        BeforeAll {
            $script:mcpServersPath = Join-Path $script:chezmoiRoot ".chezmoidata/mcp_servers.yaml"
            $script:mcpContent = Get-Content -Path $script:mcpServersPath -Raw
        }

        It 'op_env のキーが対応する env のキーに含まれていること' {
            # YAML をシンプルにパースして op_env キーが env キーに存在するか検証
            $lines = Get-Content -Path $script:mcpServersPath
            $currentEnvKeys = @()
            $currentOpEnvKeys = @()
            $currentServerName = ""
            $inEnv = $false
            $inOpEnv = $false
            $violations = @()

            foreach ($line in $lines) {
                if ($line -match '^\s+-\s+name:\s+(.+)$') {
                    # 前のサーバーの検証
                    if ($currentOpEnvKeys.Count -gt 0) {
                        foreach ($opKey in $currentOpEnvKeys) {
                            if ($opKey -notin $currentEnvKeys) {
                                $violations += "$currentServerName : op_env key '$opKey' not found in env"
                            }
                        }
                    }
                    $currentServerName = $Matches[1].Trim()
                    $currentEnvKeys = @()
                    $currentOpEnvKeys = @()
                    $inEnv = $false
                    $inOpEnv = $false
                }
                if ($line -match '^\s+env:\s*$') { $inEnv = $true; $inOpEnv = $false; continue }
                if ($line -match '^\s+op_env:\s*$') { $inOpEnv = $true; $inEnv = $false; continue }
                if ($line -match '^\s+\w+:' -and $line -notmatch '^\s+\w+:\s*\$' -and $line -notmatch '^\s+\w+:\s*"') {
                    $inEnv = $false; $inOpEnv = $false
                }
                if ($inEnv -and $line -match '^\s+(\w+):\s*"') {
                    $currentEnvKeys += $Matches[1]
                }
                if ($inOpEnv -and $line -match '^\s+(\w+):\s*"') {
                    $currentOpEnvKeys += $Matches[1]
                }
            }
            # 最後のサーバーの検証
            if ($currentOpEnvKeys.Count -gt 0) {
                foreach ($opKey in $currentOpEnvKeys) {
                    if ($opKey -notin $currentEnvKeys) {
                        $violations += "$currentServerName : op_env key '$opKey' not found in env"
                    }
                }
            }

            $violations | Should -BeNullOrEmpty -Because "op_env のキーは env にも定義されている必要がある"
        }
    }

    Context 'MCP client templates の op_env secret lookup' {
        BeforeAll {
            $script:mcpClientTemplates = @(
                "AppData/Roaming/Claude/claude_desktop_config.json.tmpl",
                "dot_claude/dot_claude.json.tmpl",
                "dot_codeium/windsurf/mcp_config.json.tmpl",
                "dot_codex/config.toml.tmpl",
                "dot_cursor/cli-config.json.tmpl",
                "dot_gemini/settings.json.tmpl"
            ) | ForEach-Object { Join-Path $script:chezmoiRoot $_ }
        }

        It 'should not call onepasswordRead during template rendering' {
            foreach ($path in $script:mcpClientTemplates) {
                $content = Get-Content -LiteralPath $path -Raw
                $content | Should -Not -Match 'onepasswordRead' -Because "$path must not fail chezmoi apply when 1Password app integration is unavailable"
            }
        }

        It 'should use non-failing op read and fall back to the configured env value' {
            foreach ($path in $script:mcpClientTemplates) {
                $content = Get-Content -LiteralPath $path -Raw
                $content | Should -Match '\$envValue := \$value' -Because "$path should keep the mcp_servers.yaml env value as fallback"
                $content | Should -Match '\bread\b.*--account' -Because "$path should resolve op_env secrets with op read"
                $content | Should -Match 'exit 0' -Because "$path should not abort template rendering on Windows op read failures"
                $content | Should -Match '\|\| true' -Because "$path should not abort template rendering on Unix op read failures"
                $content | Should -Match '\$opReadFailed' -Because "$path should stop repeated op attempts after the first failed lookup"
                $content | Should -Match "'--cache=false', 'read'" -Because "$path should disable Windows 1Password cache for noninteractive op reads"
                $content | Should -Match 'WaitForExit\(%d000\)' -Because "$path should timeout Windows op read calls"
                $content | Should -Match 'Stop-Process -Id \$process\.Id -Force' -Because "$path should terminate timed-out Windows op read calls"
                $content | Should -Match 'sleep %d; kill' -Because "$path should timeout Unix op read calls"
                $content | Should -Match 'if \$secret' -Because "$path should only replace fallback values when op returns a secret"
            }
        }
    }

    Context 'Windows MCP deploy scripts の env fallback' {
        It 'PowerShell 展開時に ${VAR} fallback を空文字にしないこと' {
            $templates = @(
                ".chezmoiscripts/deploy/editors/run_onchange_deploy_vscode_mcp.ps1.tmpl",
                ".chezmoiscripts/deploy/editors/run_onchange_deploy_zed_mcp.ps1.tmpl"
            ) | ForEach-Object { Join-Path $script:chezmoiRoot $_ }

            foreach ($path in $templates) {
                $content = Get-Content -LiteralPath $path -Raw

                $content | Should -Match '"\{\{ \$key \}\}" = ''\{\{ \$value \}\}''' -Because "$path should write mcp_servers.yaml env fallback values literally"
                $content | Should -Not -Match '"\{\{ \$key \}\}" = "\{\{ \$value \}\}"' -Because "$path must not let PowerShell expand `${VAR} fallback values"
            }
        }
    }

    Context 'Plane MCP server configuration' {
        BeforeAll {
            $script:mcpServersPath = Join-Path $script:chezmoiRoot ".chezmoidata/mcp_servers.yaml"
            $script:mcpContent = Get-Content -Path $script:mcpServersPath -Raw
            $match = [regex]::Match($script:mcpContent, '(?ms)-\s+name:\s+plane\b.*?(?=^\s+-\s+name:|\z)')
            $script:planeBlock = if ($match.Success) { $match.Value } else { "" }
        }

        It 'should configure Plane MCP over local stdio with token from the provided 1Password item' {
            $script:planeBlock | Should -Not -BeNullOrEmpty
            $script:planeBlock | Should -Match '(?m)^\s+command:\s+uvx\s*$'
            $script:planeBlock | Should -Match '(?m)^\s+-\s+"plane-mcp-server"\s*$'
            $script:planeBlock | Should -Match '(?m)^\s+-\s+"stdio"\s*$'
            $script:planeBlock | Should -Match 'PLANE_BASE_URL:\s+"http://127\.0\.0\.1:18080"'
            $script:planeBlock | Should -Match 'PLANE_WORKSPACE_SLUG:\s+"ruru"'
            $script:planeBlock | Should -Not -Match '\$\{PLANE_WORKSPACE_SLUG\}'
            $script:planeBlock | Should -Match 'PLANE_API_KEY:\s+"\$\{PLANE_API_KEY\}"'
            $script:planeBlock | Should -Match 'PLANE_API_KEY:\s+"op://hxgiw3ekjzktxf7hiyf5lyb4hi/fzhjphxau3ila6wlelo5y4ehhe/credential"'
        }

        It 'should avoid Codex auto-start because Plane depends on local service state' {
            $script:planeBlock | Should -Not -Match '(?m)^\s+-\s+codex\s*$'
        }
    }

    Context 'Shell keybindings' {
        It 'should source bashrc from profile for interactive login bash' {
            $profileContent = Get-Content -LiteralPath (Join-Path $script:chezmoiRoot "shells/profile") -Raw

            $profileContent | Should -Match '\$\{BASH_VERSION:-\}' -Because "profile is read by multiple POSIX shells and should guard bash-specific startup"
            $profileContent | Should -Match '\$HOME/\.bashrc' -Because "login bash must load the managed bash aliases"
            $profileContent | Should -Match '\*i\*\)' -Because "non-interactive login shells should not load interactive bashrc"
        }

        It 'should not calculate total directory size in eza aliases by default' {
            $shellFiles = @(
                Join-Path $script:chezmoiRoot "shells/bashrc"
                Join-Path $script:chezmoiRoot "shells/Microsoft.PowerShell_profile.ps1"
                Join-Path $script:repoRoot "nix/home/common.nix"
            )

            foreach ($path in $shellFiles) {
                $content = Get-Content -LiteralPath $path -Raw
                $content | Should -Not -Match '--total-size' -Because "$path default ls aliases must stay fast on large WSL-mounted Windows directories"
            }
        }

        It 'should keep zoxide interactive jump on Alt+Q across shells and terminals' {
            $bashrc = Get-Content -LiteralPath (Join-Path $script:chezmoiRoot "shells/bashrc") -Raw
            $powershellProfile = Get-Content -LiteralPath (Join-Path $script:chezmoiRoot "shells/Microsoft.PowerShell_profile.ps1") -Raw
            $homeManagerZsh = Get-Content -LiteralPath (Join-Path $script:repoRoot "nix/home/common.nix") -Raw
            $wezterm = Get-Content -LiteralPath (Join-Path $script:chezmoiRoot "terminals/wezterm/wezterm.lua") -Raw

            $bashrc | Should -Match 'bind -x ''"\\eq": __zoxide_zi_widget'''
            $bashrc | Should -Not -Match 'bind -x ''"\\ez": __zoxide_zi_widget'''
            $powershellProfile | Should -Match 'Set-PSReadLineKeyHandler -Chord Alt\+q -ScriptBlock \{ Invoke-ZoxideInteractive \}'
            $powershellProfile | Should -Not -Match 'Set-PSReadLineKeyHandler -Chord Alt\+z -ScriptBlock \{ Invoke-ZoxideInteractive \}'
            $homeManagerZsh | Should -Match "bindkey '\^\[q' __zoxide_zi_widget"
            $homeManagerZsh | Should -Not -Match "bindkey '\^\[z' __zoxide_zi_widget"
            $wezterm | Should -Match 'key = "q", mods = "ALT", action = act\.SendString\("\\x1bq"\)'
            $wezterm | Should -Not -Match 'key = "z", mods = "ALT", action = act\.SendString\("\\x1bz"\)'
        }
    }

    Context 'Docker MCP SDK サーバーの設定整合性' {
        BeforeAll {
            $script:mcpServersPath = Join-Path $script:chezmoiRoot ".chezmoidata/mcp_servers.yaml"
            $script:mcpLines = Get-Content -Path $script:mcpServersPath
        }

        It 'Docker MCP サーバーの args に docker run -i --rm パターンが含まれていること' {
            $content = Get-Content -Path $script:mcpServersPath -Raw
            # command: docker のサーバーを抽出
            $dockerBlocks = [regex]::Matches($content, '(?ms)-\s+name:\s+(\S+).*?command:\s+docker.*?args:.*?(?=-\s+name:|\z)')

            foreach ($block in $dockerBlocks) {
                $serverName = $block.Groups[1].Value
                $blockText = $block.Value
                $blockText | Should -Match '"run"' -Because "$serverName should have 'run' in args"
                $blockText | Should -Match '"-i"' -Because "$serverName should have '-i' for stdio"
                $blockText | Should -Match '"--rm"' -Because "$serverName should have '--rm' for cleanup"
                $blockText | Should -Match '"mcp/' -Because "$serverName should use official mcp/ namespace image"
            }
        }

        It 'Docker MCP サーバーの env で指定した変数が args の -e でも渡されていること' {
            # YAML を行単位でパースし、Docker サーバーの env キーが args に含まれるか検証
            $lines = Get-Content -Path $script:mcpServersPath
            $violations = @()
            $currentServer = ""
            $isDocker = $false
            $argsText = ""
            $envKeys = @()
            $inEnv = $false
            $inArgs = $false
            $envIndent = 0

            foreach ($line in $lines) {
                # 新サーバーエントリの開始
                if ($line -match '^\s+-\s+name:\s+(\S+)') {
                    # 前サーバーの検証
                    if ($isDocker -and $envKeys.Count -gt 0) {
                        foreach ($key in $envKeys) {
                            if ($argsText -notmatch [regex]::Escape("`"$key`"")) {
                                $violations += "$currentServer : env key '$key' not in args"
                            }
                        }
                    }
                    $currentServer = $Matches[1]
                    $isDocker = $false
                    $argsText = ""
                    $envKeys = @()
                    $inEnv = $false
                    $inArgs = $false
                    continue
                }

                if ($line -match '^\s+command:\s+docker') { $isDocker = $true }

                # args セクション
                if ($line -match '^\s+args:\s*$') { $inArgs = $true; $inEnv = $false; continue }
                if ($inArgs -and $line -match '^\s+-\s+"(.+)"') { $argsText += " `"$($Matches[1])`"" }
                if ($inArgs -and $line -match '^\s+\w+:' -and $line -notmatch '^\s+-') { $inArgs = $false }

                # env セクショ��� (op_env ではなく env: のみ)
                if ($line -match '^(\s+)env:\s*$') {
                    $envIndent = $Matches[1].Length
                    $inEnv = $true
                    $inArgs = $false
                    continue
                }
                # op_env, supports 等の別セクションに入ったら env を抜ける
                if ($inEnv -and $line -match '^\s+\w+:' -and $line -notmatch '^\s+\w+:\s*"') {
                    $inEnv = $false
                }
                if ($inEnv -and $line -match '^\s+(\w+):\s*"') {
                    $envKeys += $Matches[1]
                }
            }
            # 最後のサーバーの検証
            if ($isDocker -and $envKeys.Count -gt 0) {
                foreach ($key in $envKeys) {
                    if ($argsText -notmatch [regex]::Escape("`"$key`"")) {
                        $violations += "$currentServer : env key '$key' not in args"
                    }
                }
            }

            $violations | Should -BeNullOrEmpty -Because "Docker MCP サーバーの env 変数は args の -e で Docker に渡す必要がある"
        }

        It 'Codex Windows テンプレートでは Docker MCP が起動 wrapper 経由で実行されること' {
            $templatePath = Join-Path $script:chezmoiRoot "dot_codex/config.toml.tmpl"
            $content = Get-Content -Path $templatePath -Raw

            $content | Should -Match 'eq \.command "docker"' -Because "Docker MCP だけを wrapper 経由にする"
            $content | Should -Match 'command = "pwsh"' -Because "PowerShell 7 で wrapper を起動できる"
            $content | Should -Match 'codex-docker-mcp\.ps1' -Because "Docker Desktop の自動起動待ち wrapper を使う"
        }

        It 'Codex Windows テンプレートでは最小 Windows 環境を明示していること' {
            $templatePath = Join-Path $script:chezmoiRoot "dot_codex/config.toml.tmpl"
            $content = Get-Content -Path $templatePath -Raw

            $content | Should -Match '\[shell_environment_policy\.set\]' -Because "profile を読まない Codex 子プロセスにも env を渡す"
            $content | Should -Match 'if eq \.chezmoi\.os "windows"' -Because "Windows 固有のパスは Windows だけに出力する"
            $content | Should -Match 'env "APPDATA"' -Because "リダイレクトされた AppData パスを尊重する"
            $content | Should -Match 'env "LOCALAPPDATA"' -Because "リダイレクトされた LocalAppData パスを尊重する"
            foreach ($name in @(
                    'SystemRoot',
                    'WINDIR',
                    'ComSpec',
                    'USERPROFILE',
                    'HOME',
                    'APPDATA',
                    'LOCALAPPDATA',
                    'ProgramData',
                    'TEMP',
                    'TMP'
                )) {
                $content | Should -Match "(?m)^$name\s*=" -Because "$name は op/gh/Windows ツールの設定解決に必要"
            }

            $content | Should -Match 'env "ProgramData"' -Because "Docker Desktop backend は ProgramData が無いと起動に失敗する"
        }

        It 'should enable Codex apps for plugin-bundled connectors' {
            $templatePath = Join-Path $script:chezmoiRoot "dot_codex/config.toml.tmpl"
            $content = Get-Content -Path $templatePath -Raw

            $content | Should -Match '(?m)^apps\s*=\s*true\s*$' -Because "Gmail や Google Calendar などの app connector は features.apps が無効だと露出しない"
            $content | Should -Not -Match '(?m)^apps\s*=\s*false\s*$' -Because "chezmoi 再適用で connector 利用を無効化しない"
        }

        It 'should keep Codex project config apps enabled' {
            $projectConfigPath = Join-Path $script:repoRoot ".codex/config.toml"
            $content = Get-Content -Path $projectConfigPath -Raw

            $content | Should -Match '(?m)^apps\s*=\s*true\s*$' -Because "project-scoped config が global/chezmoi の apps=true を上書きしない"
            $content | Should -Not -Match '(?m)^apps\s*=\s*false\s*$' -Because "この repo で connector tool が露出しなくなる"
        }

        It 'project-scoped config should not re-enable noisy Codex MCP servers' {
            $projectConfigPath = Join-Path $script:repoRoot ".codex/config.toml"
            $content = Get-Content -LiteralPath $projectConfigPath -Raw

            foreach ($serverName in @('context7', 'drawio', 'playwright', 'linear', 'notion')) {
                $content | Should -Not -Match "(?m)^\[mcp_servers\.$serverName\]" -Because "$serverName should not auto-start from project config"
            }
        }

        It 'Codex Docker MCP wrapper は stdout に制御ログを書かないこと' {
            $wrapperPath = Join-Path $script:chezmoiRoot "dot_local/bin/executable_codex-docker-mcp.ps1"
            $content = Get-Content -Path $wrapperPath -Raw

            $content | Should -Match '\[Console\]::Error\.WriteLine' -Because "MCP stdio の stdout を壊さないためログは stderr に出す"
            $content | Should -Not -Match 'Write-Host' -Because "Write-Host は MCP stdio と相性が悪い"
            $content | Should -Match 'Docker Desktop\.exe' -Because "Docker daemon 未起動時に Docker Desktop を起動する"
        }
    }

    Context 'supports ID の整合性' {
        BeforeAll {
            $script:mcpServersPath = Join-Path $script:chezmoiRoot ".chezmoidata/mcp_servers.yaml"
        }

        It 'mcp_servers.yaml で旧 claude ID が残っていないこと' {
            $lines = Get-Content -Path $script:mcpServersPath
            $violations = @()
            foreach ($line in $lines) {
                # "- claude" exactly (not claude-code, claude-desktop)
                if ($line -match '^\s+-\s+claude\s*$') {
                    $violations += $line.Trim()
                }
            }
            $violations | Should -BeNullOrEmpty -Because "旧 claude ID は claude-code に移行済み"
        }

        It 'claude-code がテンプレートで正しく参照されていること' {
            $claudeTemplate = Join-Path $script:chezmoiRoot "dot_claude/dot_claude.json.tmpl"
            $content = Get-Content -Path $claudeTemplate -Raw
            $content | Should -Match 'has "claude-code"' -Because "Claude Code テンプレートは claude-code ID を使用する"
            $content | Should -Not -Match 'has "claude"[^-]' -Because "旧 claude ID は使用しない"
        }
    }

    Context 'Codex remote MCP テンプレート' {
        It 'should emit URL-based MCP as native Streamable HTTP without stdio settings' {
            $templatePath = Join-Path $script:chezmoiRoot "dot_codex/config.toml.tmpl"
            $content = Get-Content -Path $templatePath -Raw

            $marker = '{{- if hasKey . "url" }}'
            $elseMarker = '{{- else }}'
            $start = $content.IndexOf($marker, [System.StringComparison]::Ordinal)
            $start | Should -Not -Be -1 -Because "URL-based MCP の分岐が必要"

            $end = $content.IndexOf($elseMarker, $start, [System.StringComparison]::Ordinal)
            $end | Should -BeGreaterThan $start -Because "URL 分岐と stdio 分岐を分離する必要がある"

            $urlBranch = $content.Substring($start, $end - $start)
            $urlBranch | Should -Match 'url = "\{\{ \.url \}\}"' -Because "Codex は Streamable HTTP を native URL で扱える"
            $urlBranch | Should -Not -Match '(?m)^\s*command\s*=' -Because "url と stdio command を混ぜると Codex config load が失敗する"
            $urlBranch | Should -Not -Match '(?m)^\s*args\s*=' -Because "url と stdio args を混ぜると Codex config load が失敗する"
        }
    }

    Context 'Codex agent role files' {
        BeforeAll {
            $script:codexAgentFiles = Get-ChildItem -Path (Join-Path $script:chezmoiRoot "dot_codex/agents") -Filter "*.toml"
        }

        It 'should define required role metadata for Codex CLI' {
            foreach ($file in $script:codexAgentFiles) {
                $content = Get-Content -LiteralPath $file.FullName -Raw

                $content | Should -Match '(?m)^name\s*=\s*"[^"]+"\s*$' -Because "$($file.Name) must define a non-empty name"
                $content | Should -Match '(?ms)^developer_instructions\s*=\s*""".+?"""\s*$' -Because "$($file.Name) must define developer_instructions"
            }
        }

        It 'project-scoped config should not hardcode repo-local Codex paths' {
            $projectConfigPath = Join-Path $script:repoRoot ".codex/config.toml"
            $content = Get-Content -LiteralPath $projectConfigPath -Raw

            $content | Should -Not -Match '(?i)[A-Z]:[\\/].*\.codex[\\/](agents|hooks)' -Because "project config must be portable across checkout paths"
            $content | Should -Match '(?m)^config_file\s*=\s*"agents/fast_worker\.toml"\s*$' -Because "agent role files should be resolved relative to .codex/config.toml"
            $content | Should -Match '(?m)^config_file\s*=\s*"agents/python_coding\.toml"\s*$' -Because "agent role files should be resolved relative to .codex/config.toml"
            $content | Should -Match 'git rev-parse --show-toplevel' -Because "repo-local hooks should resolve from the current git root"
        }
    }

    Context 'Codex hook Python runtime policy' {
        It 'should run Windows Python hooks through uv managed Python' {
            $templatePath = Join-Path $script:chezmoiRoot "dot_codex/hooks.json.tmpl"
            $content = Get-Content -LiteralPath $templatePath -Raw

            $content | Should -Not -Match '"command":\s*"python\s+' -Because "Windows must not depend on native Python installs"
            $content | Should -Match 'uv run --isolated --managed-python python .+claude_permission_policy\.py' -Because "Codex hooks should use uv-managed Python on Windows"
            $content | Should -Match 'uv run --isolated --managed-python python .+deny_protected_branch_commit\.py' -Because "Codex hooks should use uv-managed Python on Windows"
        }
    }

    Context 'Codex MCP startup defaults' {
        BeforeAll {
            $script:mcpServersPath = Join-Path $script:chezmoiRoot ".chezmoidata/mcp_servers.yaml"
        }

        It 'should not auto-start auth or API-key MCP servers in Codex' {
            $content = Get-Content -LiteralPath $script:mcpServersPath -Raw
            $serverBlocks = [regex]::Matches($content, '(?ms)-\s+name:\s+(\S+).*?(?=^\s+-\s+name:|\z)')
            $codexDisabled = @(
                'context7',
                'linear',
                'tavily',
                'exa',
                'firecrawl',
                'drawio',
                'sentry',
                'cloud-run',
                'kaggle',
                'playwright'
            )
            $violations = @()

            foreach ($block in $serverBlocks) {
                $serverName = $block.Groups[1].Value
                if ($serverName -notin $codexDisabled) { continue }
                if ($block.Value -match '(?m)^\s+-\s+codex\s*$') {
                    $violations += $serverName
                }
            }

            $violations | Should -BeNullOrEmpty -Because "these servers require OAuth, API keys, or local cloud auth and should not warn during Codex startup"
        }

        It 'should keep OAuth plugin MCP servers disabled until login' {
            $templatePath = Join-Path $script:chezmoiRoot "dot_codex/config.toml.tmpl"
            $content = Get-Content -LiteralPath $templatePath -Raw

            foreach ($plugin in @('linear', 'notion')) {
                $block = [regex]::Match(
                    $content,
                    "(?ms)^\[plugins\.`"$plugin@openai-curated`"\]\s*.*?(?=^\[plugins\.|\z)"
                )
                $block.Success | Should -BeTrue -Because "$plugin plugin config should be explicit"
                $block.Value | Should -Match '(?m)^enabled\s*=\s*false\s*$' -Because "$plugin requires codex mcp login before startup"
            }
        }
    }

    Context 'Codex hook representation' {
        It 'should keep global hooks in hooks.json, not config.toml' {
            $hooksTemplatePath = Join-Path $script:chezmoiRoot "dot_codex/hooks.json.tmpl"
            $configTemplatePath = Join-Path $script:chezmoiRoot "dot_codex/config.toml.tmpl"
            $cleanupScript = Join-Path $script:chezmoiRoot ".chezmoiscripts/run_after_cleanup-codex-hooks-json_windows.ps1.tmpl"

            Test-Path -LiteralPath (Join-Path $script:chezmoiRoot "dot_codex/hooks.json") | Should -BeFalse
            Test-Path -LiteralPath $hooksTemplatePath | Should -BeTrue
            Test-Path -LiteralPath $cleanupScript | Should -BeFalse

            $hooksContent = Get-Content -LiteralPath $hooksTemplatePath -Raw
            $configContent = Get-Content -LiteralPath $configTemplatePath -Raw

            $hooksContent | Should -Match '"PreToolUse"' -Because 'Orca mirrors ~/.codex/hooks.json into its managed Codex runtime'
            $configContent | Should -Not -Match '(?m)^\[\[hooks\.' -Because 'config.toml hooks conflict with Orca-managed hooks.json'
        }
    }

    Context 'Orca Codex startup environment' {
        It 'should launch Orca through 1Password env-file injection' {
            $launcherPath = Join-Path $script:chezmoiRoot "dot_local/bin/executable_orca-launch.cmd"
            Test-Path -LiteralPath $launcherPath | Should -BeTrue
            $content = Get-Content -LiteralPath $launcherPath -Raw

            $content | Should -Match 'op-run-gui-launch\.ps1' -Because 'Codex MCP startup secrets should be injected through a bounded GUI launcher'
            $content | Should -Match 'DOTFILES_OP_RUN_TIMEOUT_SECONDS' -Because 'Orca startup should not hang forever when 1Password is locked'
            $content | Should -Match 'PERSONAL_ACCOUNT=EJLA3HRAVZBCXIQ7SRSFGQBTNU' -Because 'Codex MCP startup reads personal GitHub secrets before shell profiles run'
            $content | Should -Match 'WORK_ACCOUNT=aimatecoltd\.1password\.com' -Because 'work GitHub secrets live in the company 1Password account'
            $content | Should -Match 'Orca\.exe' -Because 'the launcher should start the packaged Orca app'
            $content | Should -Match 'secrets\.env' -Because 'GITHUB_PAT_TOKEN lives in the managed personal 1Password env file'
            $content | Should -Match 'secrets-work\.env' -Because 'GITHUB_WORK_TOKEN lives in the managed work 1Password env file'
            $content | Should -Match 'WinGet\\Links\\op\.exe' -Because 'Orca startup can happen before shell PATH repair'
        }

        It 'should point the Orca Start Menu shortcut at the injected launcher' {
            $scriptPath = Join-Path $script:chezmoiRoot ".chezmoiscripts/run_after_update-orca-shortcut_windows.ps1.tmpl"
            Test-Path -LiteralPath $scriptPath | Should -BeTrue
            $content = Get-Content -LiteralPath $scriptPath -Raw

            $content | Should -Match 'orca-launch\.cmd' -Because 'normal Orca launches should inherit GITHUB_PAT_TOKEN'
            $content | Should -Match 'Orca\.lnk' -Because 'the Start Menu shortcut is the launch surface Windows users normally hit'
            $content | Should -Match 'WScript\.Shell' -Because 'Windows shortcuts need COM shortcut editing'
        }

        It 'should launch direct Codex CLI through 1Password env-file injection' {
            $launcherPath = Join-Path $script:chezmoiRoot "dot_local/bin/executable_codex.cmd"
            Test-Path -LiteralPath $launcherPath | Should -BeTrue
            $content = Get-Content -LiteralPath $launcherPath -Raw

            $content | Should -Match '"%OP_EXE%" run --account "%PERSONAL_ACCOUNT%" --env-file="%PERSONAL_SECRETS_ENV%"' -Because 'direct codex CLI should satisfy personal GitHub MCP startup auth'
            $content | Should -Match '"%OP_EXE%" run --account "%WORK_ACCOUNT%" --env-file="%WORK_SECRETS_ENV%"' -Because 'direct codex CLI should inherit work GitHub token from the company account'
            $content | Should -Match 'WinGet\\Links\\codex\.exe' -Because 'the wrapper should call the real Codex executable instead of recursing through PATH'
            $content | Should -Match 'CODEX_TUI_DISABLE_KEYBOARD_ENHANCEMENT' -Because 'direct CLI should keep the existing conservative terminal input setting'
            $content | Should -Match '%SystemRoot%\\System32\\where\.exe' -Because 'Codex shells can have a trimmed PATH without System32'
            $content | Should -Match 'WinGet\\Links\\op\.exe' -Because 'direct CLI can run before shell PATH repair'
            $content | Should -Match 'if "%GITHUB_WORK_TOKEN%"=="" set "NEEDS_SECRET_LOAD=1"' -Because 'direct codex CLI should inject work secrets even when the personal token is already present'
        }
    }

    Context 'Shell config deploy script' {
        It 'should deploy secret loader files from the managed dot_config paths' {
            $scriptPaths = @(
                Join-Path $script:chezmoiRoot ".chezmoiscripts/deploy/shells/run_onchange_deploy.sh.tmpl"
                Join-Path $script:chezmoiRoot ".chezmoiscripts/deploy/shells/run_onchange_deploy.ps1.tmpl"
            )

            foreach ($scriptPath in $scriptPaths) {
                Test-Path -LiteralPath $scriptPath | Should -BeTrue
                $content = Get-Content -LiteralPath $scriptPath -Raw

                $content | Should -Match 'dot_config[\\/]shell[\\/]secret\.(sh|ps1)'
                $content | Should -Match 'dot_config[\\/]shell[\\/]secrets\.env'
                $content | Should -Match 'dot_config[\\/]shell[\\/]secrets-work\.env'
                $content | Should -Not -Match 'secret[\\/]env\.(sh|ps1)'
                $content | Should -Not -Match 'secret[\\/]secrets\.env'

                if ($scriptPath -like "*.ps1.tmpl") {
                    $content | Should -Match 'dot_local[\\/]bin[\\/]executable_wezterm-launch\.cmd'
                    $content | Should -Not -Match 'secret[\\/]wezterm-launch\.cmd'
                }
            }
        }
    }

    Context 'stdio-only テンプレートで HTTP サーバーに mcp-remote が使われていること' {
        It 'Claude Desktop テンプレートで mcp-remote が含まれていること' {
            $templatePath = Join-Path $script:chezmoiRoot "AppData/Roaming/Claude/claude_desktop_config.json.tmpl"
            if (-not (Test-Path $templatePath)) {
                Set-ItResult -Skipped -Because "Claude Desktop テンプレートが存在しない"
                return
            }
            $content = Get-Content -Path $templatePath -Raw
            $content | Should -Match 'mcp-remote' -Because "HTTP MCP サーバーは mcp-remote 経由で接続する"
        }

        It 'Windsurf テンプレートで serverUrl が使われていること' {
            $templatePath = Join-Path $script:chezmoiRoot "dot_codeium/windsurf/mcp_config.json.tmpl"
            if (-not (Test-Path $templatePath)) {
                Set-ItResult -Skipped -Because "Windsurf テンプレートが存在しない"
                return
            }
            $content = Get-Content -Path $templatePath -Raw
            $content | Should -Match 'serverUrl' -Because "Windsurf は HTTP サーバーに serverUrl を使用する"
        }
    }

    Context 'Gemini settings.json テンプレートの必須セクション' {
        BeforeAll {
            $script:geminiTemplate = Join-Path $script:chezmoiRoot "dot_gemini/settings.json.tmpl"
        }

        It 'security.auth セクションが含まれていること' {
            $content = Get-Content -Path $script:geminiTemplate -Raw
            $content | Should -Match '"security"' -Because "Gemini CLI の OAuth 認証設定が必要"
            $content | Should -Match '"selectedType"' -Because "認証タイプの指定が必要"
        }
    }

    Context 'Kaggle credentials deploy script' {
        BeforeAll {
            $script:kaggleDeployWindows = Join-Path $script:chezmoiRoot ".chezmoiscripts/deploy/kaggle/run_always_deploy.ps1.tmpl"
            $script:kaggleDeployLinux = Join-Path $script:chezmoiRoot ".chezmoiscripts/deploy/kaggle/run_always_deploy.sh.tmpl"
            $script:kaggleOldWindows = Join-Path $script:chezmoiRoot ".chezmoiscripts/deploy/kaggle/run_onchange_deploy.ps1.tmpl"
            $script:kaggleOldLinux = Join-Path $script:chezmoiRoot ".chezmoiscripts/deploy/kaggle/run_onchange_deploy.sh.tmpl"
        }

        It 'should retry on every apply instead of one-time onchange when 1Password is temporarily unavailable' {
            Test-Path -LiteralPath $script:kaggleDeployWindows | Should -BeTrue
            Test-Path -LiteralPath $script:kaggleDeployLinux | Should -BeTrue
            Test-Path -LiteralPath $script:kaggleOldWindows | Should -BeFalse
            Test-Path -LiteralPath $script:kaggleOldLinux | Should -BeFalse
        }

        It 'should not call onepasswordRead during template rendering' {
            foreach ($path in @($script:kaggleDeployWindows, $script:kaggleDeployLinux)) {
                $content = Get-Content -LiteralPath $path -Raw
                $content | Should -Not -Match 'onepasswordRead' -Because "1Password app connection failures must not abort chezmoi template rendering"
                $content | Should -Match 'ArgumentList\.Add\("read"\)|read "\$SECRET_REF"' -Because "secret lookup should happen at script runtime"
                $content | Should -Match 'ArgumentList\.Add\("--cache=false"\)|OP_CACHE_ARGS=\(--cache=false\)' -Because "Windows/op.exe runtime reads should disable 1Password cache"
                $content | Should -Match 'skipping Kaggle API credentials deployment' -Because "runtime 1Password failures should be non-fatal"
            }
        }

        It 'should bound runtime op reads with a timeout' {
            $windowsContent = Get-Content -LiteralPath $script:kaggleDeployWindows -Raw
            $linuxContent = Get-Content -LiteralPath $script:kaggleDeployLinux -Raw

            $windowsContent | Should -Match '\$OpReadTimeoutSeconds' -Because "run_always scripts must not hang when 1Password app integration prompts or stalls"
            $windowsContent | Should -Match 'WaitForExit\(\$timeoutMs\)' -Because "Windows op read should be bounded"
            $windowsContent | Should -Match 'Kill\(' -Because "timed-out Windows op reads should be terminated"
            $linuxContent | Should -Match 'OP_READ_TIMEOUT_SECONDS' -Because "run_always scripts must not hang when 1Password app integration prompts or stalls"
            $linuxContent | Should -Match 'timeout|gtimeout' -Because "Unix op read should be bounded"
            $linuxContent | Should -Match 'timed out after \$OP_READ_TIMEOUT_SECONDS seconds' -Because "timeout failures should be reported as non-fatal skips"
        }
    }

    Context 'Gemini Warp extension installer は非対話で終了すること' {
        BeforeAll {
            $script:geminiWarpWindows = Join-Path $script:chezmoiRoot ".chezmoiscripts/run_always_install-gemini-warp_windows.ps1.tmpl"
            $script:geminiWarpLinux = Join-Path $script:chezmoiRoot ".chezmoiscripts/run_always_install-gemini-warp_linux.sh.tmpl"
        }

        It 'Windows 版は trust prompt を避けるため --consent を渡すこと' {
            $content = Get-Content -Path $script:geminiWarpWindows -Raw

            $content | Should -Match '"--consent"' -Because "Gemini CLI の workspace trust prompt で chezmoi apply がハングしないようにする"
            $content | Should -Match 'extensions", "install"' -Because "Gemini extension install を明示的に実行する"
        }

        It 'Windows 版は Gemini CLI のハングを timeout で検出すること' {
            $content = Get-Content -Path $script:geminiWarpWindows -Raw

            $content | Should -Match 'DOTFILES_GEMINI_WARP_TIMEOUT_SECONDS'
            $content | Should -Match 'Start-Job'
            $content | Should -Match 'Stop-Job'
            $content | Should -Match 'timed out after \$timeoutSeconds seconds'
            $content | Should -Match 'interactive Gemini trust prompt'
        }

        It 'Gemini Warp extension install scripts はすべて consent 付きで実行すること' {
            foreach ($path in @($script:geminiWarpWindows, $script:geminiWarpLinux)) {
                $content = Get-Content -Path $path -Raw
                $content | Should -Match '--consent' -Because "$path must not prompt during chezmoi apply"
            }
        }
    }
}
