BeforeAll {
    $script:repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
    $script:adapterPath = Join-Path $script:repositoryRoot 'scripts/powershell/hermes-gmail.ps1'
    $script:originalPath = $env:PATH
    $script:originalDataDir = $env:HERMES_DATA_DIR
    $script:originalComposeFile = $env:HERMES_COMPOSE_FILE
    $script:originalCommandLog = $env:COMMAND_LOG
    $script:runningOnWindows = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
    $script:fakeBin = Join-Path $TestDrive 'bin'
    $script:dataDir = Join-Path $TestDrive 'hermes-data'
    $script:composeFile = Join-Path $TestDrive 'compose.yml'
    $script:commandLog = Join-Path $TestDrive 'commands.log'
    $script:gmailDir = Join-Path $script:dataDir 'google-gmail-mcp'
    $null = New-Item -ItemType Directory -Path (Join-Path $script:dataDir 'profiles/rick') -Force
    $null = New-Item -ItemType Directory -Path $script:gmailDir -Force
    $null = New-Item -ItemType Directory -Path $script:fakeBin -Force
    Set-Content -LiteralPath $script:composeFile -Value '' -NoNewline
    $oauth = Join-Path $script:gmailDir 'gcp-oauth.keys.json'
    Set-Content -LiteralPath $oauth -Value '{}' -NoNewline
    if (-not $script:runningOnWindows) { & chmod 600 $oauth }

    if ($script:runningOnWindows) {
        Set-Content -LiteralPath (Join-Path $script:fakeBin 'docker.cmd') -Value '@echo off' -NoNewline
        Set-Content -LiteralPath (Join-Path $script:fakeBin 'npx.cmd') -Value '@echo off' -NoNewline
    }
    else {
        $docker = Join-Path $script:fakeBin 'docker'
        $npx = Join-Path $script:fakeBin 'npx'
        $dockerScript = @'
#!/bin/sh
printf 'docker %s\n' "$*" >>"$COMMAND_LOG"
'@
        $npxScript = @'
#!/bin/sh
printf 'npx %s\n' "$*" >>"$COMMAND_LOG"
printf '{}' >"$GMAIL_CREDENTIALS_PATH"
'@
        [System.IO.File]::WriteAllText($docker, $dockerScript.Replace("`r`n", "`n"), [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::WriteAllText($npx, $npxScript.Replace("`r`n", "`n"), [System.Text.UTF8Encoding]::new($false))
        & chmod +x $docker $npx
    }
    $env:PATH = "$script:fakeBin$([System.IO.Path]::PathSeparator)$script:originalPath"
    $env:HERMES_DATA_DIR = $script:dataDir
    $env:HERMES_COMPOSE_FILE = $script:composeFile
    $env:COMMAND_LOG = $script:commandLog
}

AfterAll {
    $env:PATH = $script:originalPath
    $env:HERMES_DATA_DIR = $script:originalDataDir
    $env:HERMES_COMPOSE_FILE = $script:originalComposeFile
    $env:COMMAND_LOG = $script:originalCommandLog
}

Describe 'Hermes Gmail shared command adapter' {
    BeforeEach {
        Remove-Item -LiteralPath $script:commandLog -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath (Join-Path $script:gmailDir 'credentials.json') -Force -ErrorAction SilentlyContinue
    }

    It 'runs one shared host OAuth flow' -Skip:([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
        & $script:adapterPath -Action auth
        $LASTEXITCODE | Should -Be 0
        (Get-Content -LiteralPath $script:commandLog -Raw) | Should -Match 'npx --yes @artymclabin/gmail-mcp@1.2.3 auth --scopes=gmail.readonly,gmail.compose'
    }

    It 'rejects a profile-specific auth invocation' {
        & $script:adapterPath -Action auth -Profile rick
        $LASTEXITCODE | Should -Be 1
        Test-Path -LiteralPath $script:commandLog | Should -BeFalse
    }

    It 'uses shared credentials to test a selected profile' -Skip:([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
        $credentials = Join-Path $script:gmailDir 'credentials.json'
        Set-Content -LiteralPath $credentials -Value '{}' -NoNewline
        & chmod 600 $credentials
        & $script:adapterPath -Action test -Profile rick
        $LASTEXITCODE | Should -Be 0
        (Get-Content -LiteralPath $script:commandLog -Raw) | Should -Match 'docker compose .* run --rm --no-deps -T -e HERMES_HOME=/opt/data/profiles/rick hermes hermes mcp test gmail'
    }
}
