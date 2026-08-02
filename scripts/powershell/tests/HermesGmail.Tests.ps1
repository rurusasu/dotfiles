BeforeAll {
    $script:repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
    $script:adapterPath = Join-Path $script:repositoryRoot 'scripts/powershell/hermes-gmail.ps1'
    $script:originalPath = $env:PATH
    $script:originalDataDir = $env:HERMES_DATA_DIR
    $script:originalComposeFile = $env:HERMES_COMPOSE_FILE
    $script:originalDockerLog = $env:DOCKER_LOG
    $script:originalClientId = $env:GMAIL_MCP_CLIENT_ID
    $script:originalClientSecret = $env:GMAIL_MCP_CLIENT_SECRET

    $script:fakeBin = Join-Path $TestDrive 'bin'
    $script:dataDir = Join-Path $TestDrive 'hermes-data'
    $script:composeFile = Join-Path $TestDrive 'compose.yml'
    $script:dockerLog = Join-Path $TestDrive 'docker.log'
    $null = New-Item -ItemType Directory -Path (Join-Path $script:dataDir 'profiles/rick') -Force
    $null = New-Item -ItemType Directory -Path $script:fakeBin -Force
    Set-Content -LiteralPath $script:composeFile -Value '' -NoNewline

    if ($IsWindows) {
        Set-Content -LiteralPath (Join-Path $script:fakeBin 'docker.cmd') -Value "@echo off`r`necho %*>>`"%DOCKER_LOG%`"" -NoNewline
    }
    else {
        $dockerPath = Join-Path $script:fakeBin 'docker'
        $fakeDocker = @'
#!/usr/bin/env sh
printf '%s\n' "$*" >> "$DOCKER_LOG"
'@
        Set-Content -LiteralPath $dockerPath -Value $fakeDocker -NoNewline
        & chmod +x $dockerPath
    }

    $env:PATH = "$script:fakeBin$([System.IO.Path]::PathSeparator)$script:originalPath"
    $env:HERMES_DATA_DIR = $script:dataDir
    $env:HERMES_COMPOSE_FILE = $script:composeFile
    $env:DOCKER_LOG = $script:dockerLog
}

AfterAll {
    $env:PATH = $script:originalPath
    $env:HERMES_DATA_DIR = $script:originalDataDir
    $env:HERMES_COMPOSE_FILE = $script:originalComposeFile
    $env:DOCKER_LOG = $script:originalDockerLog
    $env:GMAIL_MCP_CLIENT_ID = $script:originalClientId
    $env:GMAIL_MCP_CLIENT_SECRET = $script:originalClientSecret
}

Describe 'Hermes Gmail command adapter' {
    BeforeEach {
        Remove-Item -LiteralPath $script:dockerLog -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath (Join-Path $script:dataDir 'profiles/rick/mcp-tokens') -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'rejects unsafe and unknown profiles before Docker starts' {
        & $script:adapterPath -Action auth -Profile '../outside'
        $LASTEXITCODE | Should -Be 1
        Test-Path -LiteralPath $script:dockerLog | Should -BeFalse

        & $script:adapterPath -Action auth -Profile missing
        $LASTEXITCODE | Should -Be 1
        Test-Path -LiteralPath $script:dockerLog | Should -BeFalse
    }

    It 'runs Gmail login in the named profile home without OAuth values in Docker arguments' {
        $tokenDir = Join-Path $script:dataDir 'profiles/rick/mcp-tokens'
        $null = New-Item -ItemType Directory -Path $tokenDir -Force
        $tokenPath = Join-Path $tokenDir 'gmail.json'
        Set-Content -LiteralPath $tokenPath -Value '{}' -NoNewline
        if (-not $IsWindows) { & chmod 600 $tokenPath }
        $env:GMAIL_MCP_CLIENT_ID = 'client-id-marker'
        $env:GMAIL_MCP_CLIENT_SECRET = 'client-secret-marker'

        & $script:adapterPath -Action auth -Profile rick
        $LASTEXITCODE | Should -Be 0

        $arguments = Get-Content -LiteralPath $script:dockerLog -Raw
        $arguments | Should -Match ([regex]::Escape("compose -f $script:composeFile run --rm --no-deps -e HERMES_HOME=/opt/data/profiles/rick hermes hermes mcp login gmail"))
        $arguments | Should -Not -Match 'client-id-marker|client-secret-marker'
    }

    It 'fails when Gmail login completes without a private token cache' {
        & $script:adapterPath -Action auth -Profile rick

        $LASTEXITCODE | Should -Be 1
        Test-Path -LiteralPath $script:dockerLog | Should -BeTrue
    }

    It 'requires a token cache before probing Gmail MCP' {
        & $script:adapterPath -Action test -Profile rick
        $LASTEXITCODE | Should -Be 1
        Test-Path -LiteralPath $script:dockerLog | Should -BeFalse
    }
}
