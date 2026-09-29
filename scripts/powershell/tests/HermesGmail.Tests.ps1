BeforeAll {
    $script:repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
    $script:adapterPath = Join-Path $script:repositoryRoot 'scripts/powershell/hermes-gmail.ps1'
    $script:originalPath = $env:PATH
    $script:originalDataDir = $env:HERMES_DATA_DIR
    $script:originalCommandLog = $env:COMMAND_LOG
    $script:runningOnWindows = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
    $script:fakeBin = Join-Path $TestDrive 'bin'
    $script:dataDir = Join-Path $TestDrive 'hermes-data'
    $script:commandLog = Join-Path $TestDrive 'commands.log'
    $script:gmailDir = Join-Path $script:dataDir 'google-gmail-mcp'
    $null = New-Item -ItemType Directory -Path (Join-Path $script:dataDir 'profiles/rick') -Force
    $null = New-Item -ItemType Directory -Path $script:gmailDir -Force
    $null = New-Item -ItemType Directory -Path $script:fakeBin -Force
    $oauth = Join-Path $script:gmailDir 'gcp-oauth.keys.json'
    Set-Content -LiteralPath $oauth -Value '{}' -NoNewline
    if (-not $script:runningOnWindows) { & chmod 600 $oauth }

    if ($script:runningOnWindows) {
        Set-Content -LiteralPath (Join-Path $script:fakeBin 'npx.cmd') -Value @'
@echo off
echo npx %*>>"%COMMAND_LOG%"
echo {}>"%GMAIL_CREDENTIALS_PATH%"
'@
    }
    else {
        $npx = Join-Path $script:fakeBin 'npx'
        $npxScript = @'
#!/bin/sh
printf 'npx %s\n' "$*" >>"$COMMAND_LOG"
printf '{}' >"$GMAIL_CREDENTIALS_PATH"
'@
        [System.IO.File]::WriteAllText($npx, $npxScript.Replace("`r`n", "`n"), [System.Text.UTF8Encoding]::new($false))
        & chmod +x $npx
    }
    $env:PATH = "$script:fakeBin$([System.IO.Path]::PathSeparator)$script:originalPath"
    $env:HERMES_DATA_DIR = $script:dataDir
    $env:COMMAND_LOG = $script:commandLog
}

AfterAll {
    $env:PATH = $script:originalPath
    $env:HERMES_DATA_DIR = $script:originalDataDir
    $env:COMMAND_LOG = $script:originalCommandLog
}

Describe 'Hermes Gmail shared command adapter' {
    BeforeEach {
        Remove-Item -LiteralPath $script:commandLog -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath (Join-Path $script:gmailDir 'credentials.json') -Force -ErrorAction SilentlyContinue
    }

    It 'should run one shared host OAuth flow with private credentials' {
        & $script:adapterPath -Action auth
        $LASTEXITCODE | Should -Be 0
        (Get-Content -LiteralPath $script:commandLog -Raw) | Should -Match 'npx --yes @artymclabin/gmail-mcp@1.2.3 auth --scopes=gmail.readonly,gmail.compose'
        if ($script:runningOnWindows) {
            $allowedSids = @(
                (Get-Acl -LiteralPath $script:gmailDir).GetOwner(
                    [System.Security.Principal.SecurityIdentifier]
                ).Value
                [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
                'S-1-5-18'
                'S-1-5-32-544'
            )
            foreach ($path in @(
                    $script:gmailDir,
                    (Join-Path $script:gmailDir 'gcp-oauth.keys.json'),
                    (Join-Path $script:gmailDir 'credentials.json')
                )) {
                $acl = Get-Acl -LiteralPath $path
                $acl.AreAccessRulesProtected | Should -BeTrue
                foreach ($access in $acl.Access) {
                    if ($access.AccessControlType -ne [System.Security.AccessControl.AccessControlType]::Allow) {
                        continue
                    }
                    $identity = $access.IdentityReference.Translate(
                        [System.Security.Principal.SecurityIdentifier]
                    ).Value
                    $allowedSids | Should -Contain $identity
                }
            }
        }
    }

    It 'should reject the removed profile-specific test action' {
        { & $script:adapterPath -Action test } | Should -Throw
        Test-Path -LiteralPath $script:commandLog | Should -BeFalse
    }
}
