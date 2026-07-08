#Requires -Module Pester

BeforeAll {
    $script:repoRoot = Join-Path $PSScriptRoot "../../../../"
    $script:chezmoiRoot = Join-Path $script:repoRoot "chezmoi"
    $script:helperPath = Join-Path $script:chezmoiRoot "dot_config/shell/gh-token-switch.ps1"
    $script:secretLoaderPath = Join-Path $script:chezmoiRoot "dot_config/shell/secret.ps1"
    $script:weztermLaunch = Join-Path $script:chezmoiRoot "dot_local/bin/executable_wezterm-launch.cmd"
}

AfterAll {
    Remove-Item Function:\gh -ErrorAction SilentlyContinue
    Remove-Item Function:\Invoke-DotfilesGitHubCli -ErrorAction SilentlyContinue
    Remove-Item Function:\Resolve-DotfilesGitHubCli -ErrorAction SilentlyContinue
    Remove-Item Function:\Test-DotfilesWorkGitHubRepository -ErrorAction SilentlyContinue
}

Describe 'PowerShell secret loader' {
    BeforeEach {
        $script:previousGhToken = [Environment]::GetEnvironmentVariable('GH_TOKEN', 'Process')
        $script:previousGitHubPatToken = [Environment]::GetEnvironmentVariable('GITHUB_PAT_TOKEN', 'Process')
        $script:previousTavilyApiKey = [Environment]::GetEnvironmentVariable('TAVILY_API_KEY', 'Process')
        $script:previousWorkToken = [Environment]::GetEnvironmentVariable('GITHUB_WORK_TOKEN', 'Process')
        $script:previousOpBin = [Environment]::GetEnvironmentVariable('DOTFILES_OP_BIN', 'Process')
        $script:previousSecretTimeout = [Environment]::GetEnvironmentVariable('DOTFILES_SECRET_LOAD_TIMEOUT_SECONDS', 'Process')
        $script:previousForceSecretLoad = [Environment]::GetEnvironmentVariable('DOTFILES_FORCE_SECRET_LOAD', 'Process')

        Remove-Item Env:GH_TOKEN -ErrorAction SilentlyContinue
        Remove-Item Env:GITHUB_PAT_TOKEN -ErrorAction SilentlyContinue
        Remove-Item Env:TAVILY_API_KEY -ErrorAction SilentlyContinue
        Remove-Item Env:GITHUB_WORK_TOKEN -ErrorAction SilentlyContinue
        $env:DOTFILES_SECRET_LOAD_TIMEOUT_SECONDS = '3'
        $env:DOTFILES_FORCE_SECRET_LOAD = '1'
    }

    AfterEach {
        if ($null -eq $script:previousGhToken) {
            Remove-Item Env:GH_TOKEN -ErrorAction SilentlyContinue
        }
        else {
            $env:GH_TOKEN = $script:previousGhToken
        }

        if ($null -eq $script:previousGitHubPatToken) {
            Remove-Item Env:GITHUB_PAT_TOKEN -ErrorAction SilentlyContinue
        }
        else {
            $env:GITHUB_PAT_TOKEN = $script:previousGitHubPatToken
        }

        if ($null -eq $script:previousTavilyApiKey) {
            Remove-Item Env:TAVILY_API_KEY -ErrorAction SilentlyContinue
        }
        else {
            $env:TAVILY_API_KEY = $script:previousTavilyApiKey
        }

        if ($null -eq $script:previousWorkToken) {
            Remove-Item Env:GITHUB_WORK_TOKEN -ErrorAction SilentlyContinue
        }
        else {
            $env:GITHUB_WORK_TOKEN = $script:previousWorkToken
        }

        if ($null -eq $script:previousOpBin) {
            Remove-Item Env:DOTFILES_OP_BIN -ErrorAction SilentlyContinue
        }
        else {
            $env:DOTFILES_OP_BIN = $script:previousOpBin
        }

        if ($null -eq $script:previousSecretTimeout) {
            Remove-Item Env:DOTFILES_SECRET_LOAD_TIMEOUT_SECONDS -ErrorAction SilentlyContinue
        }
        else {
            $env:DOTFILES_SECRET_LOAD_TIMEOUT_SECONDS = $script:previousSecretTimeout
        }

        if ($null -eq $script:previousForceSecretLoad) {
            Remove-Item Env:DOTFILES_FORCE_SECRET_LOAD -ErrorAction SilentlyContinue
        }
        else {
            $env:DOTFILES_FORCE_SECRET_LOAD = $script:previousForceSecretLoad
        }
    }

    It '環境変数が未設定なら op inject から PowerShell process 環境に読み込むこと' {
        $fakeOp = Join-Path $TestDrive 'op.cmd'
        Set-Content -LiteralPath $fakeOp -Encoding ascii -Value @'
@echo off
if "%1"=="inject" if "%2"=="--in-file" if exist "%3" if "%4"=="--account" if "%5"=="EJLA3HRAVZBCXIQ7SRSFGQBTNU" (
  echo GITHUB_PAT_TOKEN=personal-token
  echo TAVILY_API_KEY=tavily-token
  exit /b 0
)
if "%1"=="inject" if "%2"=="--in-file" if exist "%3" if "%4"=="--account" if "%5"=="aimatecoltd.1password.com" (
  echo GITHUB_WORK_TOKEN=work-token
  exit /b 0
)
exit /b 1
'@
        $env:DOTFILES_OP_BIN = $fakeOp

        . $script:secretLoaderPath

        $env:GITHUB_PAT_TOKEN | Should -Be 'personal-token'
        $env:GH_TOKEN | Should -Be 'personal-token'
        $env:TAVILY_API_KEY | Should -Be 'tavily-token'
        $env:GITHUB_WORK_TOKEN | Should -Be 'work-token'
    }

    It 'op inject が失敗しても shell 起動を例外で止めないこと' {
        $fakeOp = Join-Path $TestDrive 'op-fail.cmd'
        Set-Content -LiteralPath $fakeOp -Encoding ascii -Value @'
@echo off
exit /b 42
'@
        $env:DOTFILES_OP_BIN = $fakeOp

        $previousWarningPreference = $WarningPreference
        try {
            $WarningPreference = 'SilentlyContinue'
            { . $script:secretLoaderPath } | Should -Not -Throw
        }
        finally {
            $WarningPreference = $previousWarningPreference
        }

        $env:GH_TOKEN | Should -BeNullOrEmpty
        $env:GITHUB_WORK_TOKEN | Should -BeNullOrEmpty
    }

    It 'pwsh -Command では force 未設定なら fallback を起動しないこと' {
        $fakeOp = Join-Path $TestDrive 'op-marker.cmd'
        $marker = Join-Path $TestDrive 'op-called.txt'
        Set-Content -LiteralPath $fakeOp -Encoding ascii -Value @"
@echo off
echo called>"$marker"
echo GH_TOKEN=personal-token
echo TAVILY_API_KEY=tavily-token
echo GITHUB_WORK_TOKEN=work-token
exit /b 0
"@
        Remove-Item Env:DOTFILES_FORCE_SECRET_LOAD -ErrorAction SilentlyContinue

        $loader = $script:secretLoaderPath.Replace("'", "''")
        $fakeOpLiteral = $fakeOp.Replace("'", "''")
        $command = @"
`$env:DOTFILES_OP_BIN = '$fakeOpLiteral'
`$env:DOTFILES_SECRET_LOAD_TIMEOUT_SECONDS = '3'
Remove-Item Env:DOTFILES_FORCE_SECRET_LOAD -ErrorAction SilentlyContinue
Remove-Item Env:GH_TOKEN -ErrorAction SilentlyContinue
Remove-Item Env:GITHUB_PAT_TOKEN -ErrorAction SilentlyContinue
Remove-Item Env:TAVILY_API_KEY -ErrorAction SilentlyContinue
Remove-Item Env:GITHUB_WORK_TOKEN -ErrorAction SilentlyContinue
. '$loader'
[Console]::WriteLine('gh=' + [bool]`$env:GH_TOKEN)
[Console]::WriteLine('githubPat=' + [bool]`$env:GITHUB_PAT_TOKEN)
"@

        $output = & pwsh -NoLogo -NoProfile -Command $command

        $output | Should -Contain 'gh=False'
        $output | Should -Contain 'githubPat=False'
        Test-Path -LiteralPath $marker | Should -BeFalse
    }
}

Describe 'GitHub token switching helper (PowerShell)' {
    BeforeEach {
        $script:previousGhToken = [Environment]::GetEnvironmentVariable('GH_TOKEN', 'Process')
        $script:previousWorkToken = [Environment]::GetEnvironmentVariable('GITHUB_WORK_TOKEN', 'Process')
        $script:previousGhBin = [Environment]::GetEnvironmentVariable('DOTFILES_GH_BIN', 'Process')

        . $script:helperPath

        $script:tempRepo = Join-Path $TestDrive ([Guid]::NewGuid().ToString('N'))
        $script:fakeGh = Join-Path $TestDrive "fake-gh.ps1"
        New-Item -ItemType Directory -Path $script:tempRepo -Force | Out-Null
        Set-Content -LiteralPath $script:fakeGh -Value @'
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$RemainingArgs)
"token=$env:GH_TOKEN"
"args=$($RemainingArgs -join ',')"
exit 23
'@
        $env:DOTFILES_GH_BIN = $script:fakeGh
    }

    AfterEach {
        if ($null -eq $script:previousGhToken) {
            Remove-Item Env:GH_TOKEN -ErrorAction SilentlyContinue
        }
        else {
            $env:GH_TOKEN = $script:previousGhToken
        }

        if ($null -eq $script:previousWorkToken) {
            Remove-Item Env:GITHUB_WORK_TOKEN -ErrorAction SilentlyContinue
        }
        else {
            $env:GITHUB_WORK_TOKEN = $script:previousWorkToken
        }

        if ($null -eq $script:previousGhBin) {
            Remove-Item Env:DOTFILES_GH_BIN -ErrorAction SilentlyContinue
        }
        else {
            $env:DOTFILES_GH_BIN = $script:previousGhBin
        }
    }

    It 'git@github-work remote の repo では GITHUB_WORK_TOKEN を GH_TOKEN として使うこと' {
        Push-Location $script:tempRepo
        try {
            git init | Out-Null
            git remote add origin 'git@github-work:org/repo.git'
            $env:GH_TOKEN = 'personal-token'
            $env:GITHUB_WORK_TOKEN = 'work-token'

            $output = Invoke-DotfilesGitHubCli pr list 2>$null

            $output | Should -Contain 'token=work-token'
            $output | Should -Contain 'args=pr,list'
            $env:GH_TOKEN | Should -Be 'personal-token' -Because 'wrapper 実行後は元の GH_TOKEN に戻す'
            $LASTEXITCODE | Should -Be 23
        }
        finally {
            Pop-Location
        }
    }

    It 'personal remote の repo では既存 GH_TOKEN を維持すること' {
        Push-Location $script:tempRepo
        try {
            git init | Out-Null
            git remote add origin 'git@github.com:rurusasu/dotfiles.git'
            $env:GH_TOKEN = 'personal-token'
            $env:GITHUB_WORK_TOKEN = 'work-token'

            $output = Invoke-DotfilesGitHubCli issue list 2>$null

            $output | Should -Contain 'token=personal-token'
            $env:GH_TOKEN | Should -Be 'personal-token'
            $LASTEXITCODE | Should -Be 23
        }
        finally {
            Pop-Location
        }
    }

    It 'Windows work root 配下では work repo と判定すること' {
        Test-DotfilesWorkGitHubRepository -Path 'D:\my_programing\org\repo' | Should -BeTrue
    }

    It 'personal root 配下では path だけで work repo と判定しないこと' {
        Test-DotfilesWorkGitHubRepository -Path 'D:\ruru\dotfiles' | Should -BeFalse
    }

    It 'work repo で GITHUB_WORK_TOKEN が未設定なら GH_TOKEN を壊さないこと' {
        Push-Location $script:tempRepo
        try {
            git init | Out-Null
            git remote add origin 'git@github-work:org/repo.git'
            $env:GH_TOKEN = 'personal-token'
            Remove-Item Env:GITHUB_WORK_TOKEN -ErrorAction SilentlyContinue

            $output = Invoke-DotfilesGitHubCli repo view 3>$null

            $output | Should -Contain 'token=personal-token'
            $env:GH_TOKEN | Should -Be 'personal-token'
        }
        finally {
            Pop-Location
        }
    }
}

Describe 'GitHub token switching templates' {
    It 'PowerShell profile が gh token switching helper を読み込むこと' {
        $profilePath = Join-Path $script:chezmoiRoot "shells/Microsoft.PowerShell_profile.ps1"
        $content = Get-Content -LiteralPath $profilePath -Raw

        $content | Should -Match 'gh-token-switch\.ps1'
    }

    It 'PowerShell profile の codex wrapper が 1Password env-file injection を使うこと' {
        $profilePath = Join-Path $script:chezmoiRoot "shells/Microsoft.PowerShell_profile.ps1"
        $content = Get-Content -LiteralPath $profilePath -Raw

        $content | Should -Match 'GITHUB_PAT_TOKEN' -Because 'GitHub plugin MCP reads GITHUB_PAT_TOKEN from the Codex process environment'
        $content | Should -Match 'opArgs\s*=\s*@\("run", "--env-file", \$secretsEnv, "--", \$codexCommand\.Source\)' -Because 'codex should be launched through op run when the token is not already set'
        $content | Should -Match '\.config\\shell\\secrets\.env' -Because 'the managed 1Password env file is the source of Codex process secrets'
    }

    It 'bashrc が gh token switching helper を読み込むこと' {
        $bashrcPath = Join-Path $script:chezmoiRoot "shells/bashrc"
        $content = Get-Content -LiteralPath $bashrcPath -Raw

        $content | Should -Match 'gh-token-switch\.sh'
    }

    It 'Home Manager zsh init が gh token switching helper を読み込むこと' {
        $commonNixPath = Join-Path $script:repoRoot "nix/home/common.nix"
        $content = Get-Content -LiteralPath $commonNixPath -Raw

        $content | Should -Match 'gh-token-switch\.sh'
    }

    It 'WezTerm launcher が GITHUB_WORK_TOKEN を WSL に渡すこと' {
        $content = Get-Content -LiteralPath $script:weztermLaunch -Raw

        $content | Should -Match 'WSLENV=GITHUB_PAT_TOKEN:TAVILY_API_KEY:GITHUB_WORK_TOKEN'
        $content | Should -Not -Match 'WSLENV=GH_TOKEN'
        $content | Should -Match 'WSLENV=.*GITHUB_WORK_TOKEN'
    }

    It 'Orca launcher が GITHUB_PAT_TOKEN を Codex process に渡すこと' {
        $orcaLaunch = Join-Path $script:chezmoiRoot "dot_local/bin/executable_orca-launch.cmd"
        $content = Get-Content -LiteralPath $orcaLaunch -Raw

        $content | Should -Match '"%OP_EXE%" run --env-file="%SECRETS_ENV%"' -Because 'GitHub MCP checks GITHUB_PAT_TOKEN during Codex startup'
        $content | Should -Match 'Orca\.exe'
        $content | Should -Match 'WinGet\\Links\\op\.exe'
        $content | Should -Match 'secrets\.env'
    }

    It 'Codex CLI launcher が GITHUB_PAT_TOKEN を Codex process に渡すこと' {
        $codexLaunch = Join-Path $script:chezmoiRoot "dot_local/bin/executable_codex.cmd"
        $content = Get-Content -LiteralPath $codexLaunch -Raw

        $content | Should -Match '"%OP_EXE%" run --env-file="%SECRETS_ENV%"' -Because 'GitHub MCP checks GITHUB_PAT_TOKEN during Codex startup'
        $content | Should -Match 'codex\.exe'
        $content | Should -Match 'WinGet\\Links\\op\.exe'
        $content | Should -Match 'GITHUB_PAT_TOKEN'
        $content | Should -Match 'secrets\.env'
    }

    It 'secrets.env が work token の 1Password 参照を含むこと' {
        $secretsEnvPath = Join-Path $script:chezmoiRoot "dot_config/shell/secrets.env"
        $content = Get-Content -LiteralPath $secretsEnvPath -Raw

        $content | Should -Match 'GITHUB_PAT_TOKEN=op://Private/GitHubUsedUserPAT/credential'
        $content | Should -Not -Match '^GH_TOKEN=op://Private/GitHubUsedUserPAT/credential'
        $content | Should -Match 'GITHUB_WORK_TOKEN=op://devcontainer/GITHUB_PERSONAL_ACCESS_TOKEN_KOHEI-MIKI-IM8/credential'
    }

    It 'PowerShell secret loader の guard が GITHUB_WORK_TOKEN を含むこと' {
        $secretPs1Path = Join-Path $script:chezmoiRoot "dot_config/shell/secret.ps1"
        $content = Get-Content -LiteralPath $secretPs1Path -Raw

        $content | Should -Match 'GITHUB_PAT_TOKEN'
        $content | Should -Match 'GITHUB_WORK_TOKEN'
    }

    It 'secret loader files are stored at the managed shell config paths' {
        Test-Path -LiteralPath (Join-Path $script:chezmoiRoot "dot_config/shell/secret.ps1") | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:chezmoiRoot "dot_config/shell/secret.sh") | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:chezmoiRoot "dot_config/shell/secrets.env") | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:chezmoiRoot "secret") | Should -BeFalse
    }
}
