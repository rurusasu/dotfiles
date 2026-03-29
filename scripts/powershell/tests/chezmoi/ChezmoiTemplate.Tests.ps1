#Requires -Module Pester

<#
.SYNOPSIS
    chezmoi テンプレート (.tmpl) のバリデーションテスト

.DESCRIPTION
    AGENTS.md のルールに基づき、テンプレートの安全性を静的に検証する:
    - onepasswordRead は lookPath "op" でガードされているか
    - 主要テンプレートに必須セクションが含まれているか
#>

BeforeAll {
    $script:chezmoiRoot = Join-Path $PSScriptRoot "../../../../chezmoi"
    $script:templateFiles = Get-ChildItem -Path $script:chezmoiRoot -Filter "*.tmpl" -Recurse
}

Describe 'chezmoi テンプレート バリデーション' {
    Context 'onepasswordRead には lookPath "op" ガードが必須' {
        It 'すべての .tmpl ファイルで onepasswordRead が lookPath "op" でガードされていること' {
            $violations = @()

            foreach ($file in $script:templateFiles) {
                $content = Get-Content -Path $file.FullName -Raw -ErrorAction SilentlyContinue
                if (-not $content) { continue }

                # onepasswordRead を含むがファイル全体に lookPath "op" が無い場合は違反
                if ($content -match 'onepasswordRead' -and $content -notmatch 'lookPath\s+"op"') {
                    $violations += $file.FullName
                }
            }

            $violations | Should -BeNullOrEmpty -Because (
                "AGENTS.md ルール: onepasswordRead を使う箇所は lookPath `"op`" でガードすること。" +
                " 違反ファイル: $($violations -join ', ')"
            )
        }

        It 'onepasswordRead の各呼び出しが個別に lookPath ブロック内にあること' {
            foreach ($file in $script:templateFiles) {
                $lines = Get-Content -Path $file.FullName -ErrorAction SilentlyContinue
                if (-not $lines) { continue }

                $inOpGuard = $false
                # $hasOp 変数経由の間接ガードも検出する
                # パターン: $hasOp := and (hasKey . "op_env") (lookPath "op")
                #           if and $hasOp ...
                $hasOpVarGuard = $false
                $inHasOpBlock = $false
                $lineNum = 0

                foreach ($line in $lines) {
                    $lineNum++

                    # 直接ガード: {{- if lookPath "op" }}
                    if ($line -match '\{\{-?\s*if\s+lookPath\s+"op"') {
                        $inOpGuard = $true
                    }

                    # 間接ガード: $hasOp := and ... (lookPath "op")
                    if ($line -match '\$hasOp\s*:=\s*and\s.*lookPath\s+"op"') {
                        $hasOpVarGuard = $true
                    }

                    # 間接ガードブロック開始: {{- if and $hasOp ...
                    if ($line -match '\{\{-?\s*if\s+and\s+\$hasOp' -and $hasOpVarGuard) {
                        $inHasOpBlock = $true
                    }

                    if ($line -match 'onepasswordRead' -and -not $inOpGuard -and -not $inHasOpBlock) {
                        "$($file.Name):$lineNum should be inside a lookPath `"op`" block" |
                            Should -BeNullOrEmpty
                    }

                    if ($line -match '\{\{-?\s*end\s*\}\}') {
                        if ($inHasOpBlock) { $inHasOpBlock = $false }
                        elseif ($inOpGuard) { $inOpGuard = $false }
                    }
                }
            }
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
}
