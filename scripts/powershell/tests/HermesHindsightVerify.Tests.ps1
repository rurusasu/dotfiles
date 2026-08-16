BeforeAll {
    $script:repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
    $script:entrypointPath = Join-Path $script:repositoryRoot 'scripts/powershell/hermes-hindsight-verify.ps1'
    . $script:entrypointPath
}

Describe 'Hermes Hindsight PowerShell acceptance entrypoint' {
    BeforeEach {
        $script:composeDirectory = Join-Path $TestDrive 'compose'
        $script:composeFile = Join-Path $script:composeDirectory 'compose.yml'
        $script:dataDir = Join-Path $TestDrive 'hermes-data'
        $script:stateFile = Join-Path $script:dataDir 'hindsight/acceptance-state.json'
        $script:calls = [System.Collections.Generic.List[string]]::new()
        $script:aliveResponse = 'HERMES_ALIVE'
        $script:dockerFailureMatch = ''
        $global:LASTEXITCODE = 0

        $null = New-Item -ItemType Directory -Path $script:composeDirectory -Force
        $null = New-Item -ItemType Directory -Path (Split-Path -Parent $script:stateFile) -Force
        Set-Content -LiteralPath $script:composeFile -Value 'services: {}' -Encoding utf8
        Set-Content -LiteralPath (Join-Path $script:composeDirectory 'hindsight.env') -Value @(
            'HINDSIGHT_API_LLM_MODEL=qwen3.6:35b'
            'HINDSIGHT_API_EMBEDDINGS_OPENAI_MODEL=qwen3-embedding:0.6b'
        ) -Encoding utf8
        Set-Content -LiteralPath $script:stateFile -Value '{"run_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","banks":{"default":"test-hermes-default-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","shiraishi":"test-hermes-shiraishi-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}}' -Encoding utf8
        $script:stateBefore = Get-Content -LiteralPath $script:stateFile -Raw

        foreach ($name in @(
                'HINDSIGHT_OLLAMA_READY_ATTEMPTS',
                'HINDSIGHT_OLLAMA_READY_DELAY_SECONDS',
                'HINDSIGHT_API_READY_ATTEMPTS',
                'HINDSIGHT_API_READY_DELAY_SECONDS',
                'HERMES_API_PORT'
            )) {
            Remove-Item -LiteralPath "Env:\$name" -ErrorAction SilentlyContinue
        }
        $env:HINDSIGHT_OLLAMA_READY_ATTEMPTS = '1'
        $env:HINDSIGHT_OLLAMA_READY_DELAY_SECONDS = '0'
        $env:HINDSIGHT_API_READY_ATTEMPTS = '1'
        $env:HINDSIGHT_API_READY_DELAY_SECONDS = '0'

        Mock Get-ExternalCommand {
            [PSCustomObject]@{ Name = $Name; Source = $Name }
        }

        Mock Invoke-HermesHindsightCommand {
            $line = "$Command $($Arguments -join ' ')"
            $script:calls.Add($line)
            if ($Command -eq 'curl' -and $Arguments[-1] -eq 'http://127.0.0.1:11434/api/version') {
                return '{"version":"1.0.0"}'
            }
            if ($Command -eq 'curl' -and $Arguments[-1] -eq 'http://127.0.0.1:11434/api/tags') {
                return '{"models":[{"name":"qwen3.6:35b"},{"name":"qwen3-embedding:0.6b"}]}'
            }
            if ($Command -eq 'curl' -and $Arguments[-1] -eq 'http://127.0.0.1:8888/health') {
                return '{"status":"healthy","database":"connected"}'
            }
            if ($Command -eq 'curl' -and $Arguments[-1] -eq 'http://127.0.0.1:8642/health') {
                return '{"status":"ok"}'
            }
            return @()
        }

        Mock Invoke-Docker {
            $line = "docker $($Arguments -join ' ')"
            $script:calls.Add($line)
            if (-not [string]::IsNullOrWhiteSpace($script:dockerFailureMatch) -and
                $line.Contains($script:dockerFailureMatch, [System.StringComparison]::Ordinal)) {
                $global:LASTEXITCODE = 42
                return @()
            }
            $global:LASTEXITCODE = 0
            if ($line.Contains('exec -T hermes hermes chat --quiet -q', [System.StringComparison]::Ordinal)) {
                return $script:aliveResponse
            }
            return @()
        }

        Mock Start-Sleep
    }

    AfterEach {
        foreach ($name in @(
                'HINDSIGHT_OLLAMA_READY_ATTEMPTS',
                'HINDSIGHT_OLLAMA_READY_DELAY_SECONDS',
                'HINDSIGHT_API_READY_ATTEMPTS',
                'HINDSIGHT_API_READY_DELAY_SECONDS',
                'HERMES_API_PORT'
            )) {
            Remove-Item -LiteralPath "Env:\$name" -ErrorAction SilentlyContinue
        }
    }

    It 'should run all eleven phases in exact order and clean up only after recovery' {
        Invoke-HermesHindsightVerify -ComposeFile $script:composeFile -DataDir $script:dataDir

        $script:calls | Should -Be @(
            "docker compose -f $script:composeFile config --quiet"
            'curl --fail --silent --show-error --max-time 2 http://127.0.0.1:11434/api/version'
            'ollama pull qwen3.6:35b'
            'ollama pull qwen3-embedding:0.6b'
            'curl --fail --silent --show-error --max-time 2 http://127.0.0.1:11434/api/tags'
            "docker compose -f $script:composeFile up -d hindsight"
            'curl --fail --silent --show-error --max-time 2 http://127.0.0.1:8888/health'
            "docker compose -f $script:composeFile exec -T hermes hermes-hindsight-acceptance probe --api-url http://hindsight:8888 --ollama-url http://host.docker.internal:11434 --strict-probes 20 --timeout 300 --evidence /opt/data/hindsight/acceptance.json"
            "docker compose -f $script:composeFile exec -T hermes hermes-hindsight-acceptance seed --api-url http://hindsight:8888 --profiles default,rick,hoffman,risarisa,nancy,kuroda,shiraishi --timeout 300 --state /opt/data/hindsight/acceptance-state.json"
            "docker compose -f $script:composeFile restart hindsight"
            'curl --fail --silent --show-error --max-time 2 http://127.0.0.1:8888/health'
            "docker compose -f $script:composeFile exec -T hermes hermes-hindsight-acceptance verify --api-url http://hindsight:8888 --timeout 300 --state /opt/data/hindsight/acceptance-state.json --evidence /opt/data/hindsight/acceptance.json"
            "docker compose -f $script:composeFile stop hindsight"
            "docker compose -f $script:composeFile exec -T hermes hermes-hindsight-acceptance degraded --api-url http://hindsight:8888 --timeout 5 --state /opt/data/hindsight/acceptance-state.json --evidence /opt/data/hindsight/acceptance.json"
            'docker compose -f ' + $script:composeFile + ' exec -T hermes hermes chat --quiet -q Reply with exactly HERMES_ALIVE and nothing else.'
            'curl --fail --silent --show-error --max-time 5 http://127.0.0.1:8642/health'
            "docker compose -f $script:composeFile start hindsight"
            'curl --fail --silent --show-error --max-time 2 http://127.0.0.1:8888/health'
            "docker compose -f $script:composeFile exec -T hermes hermes-hindsight-acceptance recovery --api-url http://hindsight:8888 --timeout 300 --state /opt/data/hindsight/acceptance-state.json --evidence /opt/data/hindsight/acceptance.json"
            "docker compose -f $script:composeFile exec -T hermes hermes-hindsight-acceptance cleanup --api-url http://hindsight:8888 --state /opt/data/hindsight/acceptance-state.json --evidence /opt/data/hindsight/acceptance.json"
        )
        $recovery = $script:calls.IndexOf("docker compose -f $script:composeFile start hindsight")
        $cleanup = $script:calls.IndexOf("docker compose -f $script:composeFile exec -T hermes hermes-hindsight-acceptance cleanup --api-url http://hindsight:8888 --state /opt/data/hindsight/acceptance-state.json --evidence /opt/data/hindsight/acceptance.json")
        $cleanup | Should -BeGreaterThan $recovery
    }

    It 'should reject a nonexact one-shot response, restart Hindsight, and skip cleanup' {
        $script:aliveResponse = 'HERMES_ALIVE extra'

        { Invoke-HermesHindsightVerify -ComposeFile $script:composeFile -DataDir $script:dataDir } |
            Should -Throw '*exact HERMES_ALIVE*'

        $script:calls | Should -Contain "docker compose -f $script:composeFile start hindsight"
        ($script:calls -join "`n") | Should -Not -Match 'acceptance cleanup'
        (Get-Content -LiteralPath $script:stateFile -Raw) | Should -BeExactly $script:stateBefore
    }

    It 'should reject a one-shot response with leading whitespace' {
        $script:aliveResponse = ' HERMES_ALIVE'

        { Invoke-HermesHindsightVerify -ComposeFile $script:composeFile -DataDir $script:dataDir } |
            Should -Throw '*exact HERMES_ALIVE*'
    }

    It 'should reject a one-shot response with trailing whitespace' {
        $script:aliveResponse = 'HERMES_ALIVE '

        { Invoke-HermesHindsightVerify -ComposeFile $script:composeFile -DataDir $script:dataDir } |
            Should -Throw '*exact HERMES_ALIVE*'
    }

    It 'should reject a one-shot response with surrounding whitespace' {
        $script:aliveResponse = ' HERMES_ALIVE '

        { Invoke-HermesHindsightVerify -ComposeFile $script:composeFile -DataDir $script:dataDir } |
            Should -Throw '*exact HERMES_ALIVE*'
    }

    It 'should stop at the first failed phase and preserve exact failed-run bank state' {
        $script:dockerFailureMatch = 'hermes-hindsight-acceptance verify'

        { Invoke-HermesHindsightVerify -ComposeFile $script:composeFile -DataDir $script:dataDir } |
            Should -Throw '*exit code 42*'

        ($script:calls -join "`n") | Should -Match 'acceptance verify'
        ($script:calls -join "`n") | Should -Not -Match 'stop hindsight|acceptance cleanup'
        (Get-Content -LiteralPath $script:stateFile -Raw) | Should -BeExactly $script:stateBefore
        $script:stateBefore | Should -Match 'test-hermes-shiraishi-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    }

    It 'should restart Hindsight when degraded verification fails after stop' {
        $script:dockerFailureMatch = 'hermes-hindsight-acceptance degraded'

        { Invoke-HermesHindsightVerify -ComposeFile $script:composeFile -DataDir $script:dataDir } |
            Should -Throw '*exit code 42*'

        $script:calls | Should -Contain "docker compose -f $script:composeFile stop hindsight"
        $script:calls | Should -Contain "docker compose -f $script:composeFile start hindsight"
        ($script:calls -join "`n") | Should -Not -Match 'acceptance cleanup'
    }
}
