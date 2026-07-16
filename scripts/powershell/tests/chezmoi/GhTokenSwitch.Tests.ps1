#Requires -Module Pester

BeforeAll {
    $script:repoRoot = Join-Path $PSScriptRoot "../../../../"
    $script:chezmoiRoot = Join-Path $script:repoRoot "chezmoi"
    $script:helperPath = Join-Path $script:chezmoiRoot "dot_config/shell/gh-token-switch.ps1"
    $script:secretLoaderPath = Join-Path $script:chezmoiRoot "dot_config/shell/secret.ps1"
    $script:weztermLaunch = Join-Path $script:chezmoiRoot "dot_local/bin/executable_wezterm-launch.cmd"
    $script:codexLaunch = Join-Path $script:chezmoiRoot "dot_local/bin/executable_codex.cmd"
    $script:codexLoginPreflight = Join-Path $script:chezmoiRoot "dot_local/bin/executable_stop-stale-codex-login.ps1"
    $script:orcaLaunch = Join-Path $script:chezmoiRoot "dot_local/bin/executable_orca-launch.cmd"
    $script:bashrcPath = Join-Path $script:chezmoiRoot "shells/bashrc"
    $script:commonNixPath = Join-Path $script:repoRoot "nix/home/common.nix"
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

    It '環境変数が未設定なら op read から PowerShell process 環境に読み込むこと' {
        $fakeOp = Join-Path $TestDrive 'op.cmd'
        Set-Content -LiteralPath $fakeOp -Encoding ascii -Value @'
@echo off
set "ARGS=%*"
if not "%ARGS:GitHubUsedUserPAT=%"=="%ARGS%" (
  echo personal-token
  exit /b 0
)
if not "%ARGS:TavilyUsedUserPAT=%"=="%ARGS%" (
  echo tavily-token
  exit /b 0
)
if not "%ARGS:GITHUB_PERSONAL_ACCESS_TOKEN_KOHEI-MIKI-IM8=%"=="%ARGS%" (
  echo work-token
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

    It 'op read が失敗しても shell 起動を例外で止めないこと' {
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

    It 'PowerShell profile 読み込みでは force 未設定なら fallback を起動しないこと' {
        $fakeOp = Join-Path $TestDrive 'op-profile-marker.cmd'
        $marker = Join-Path $TestDrive 'op-profile-called.txt'
        Set-Content -LiteralPath $fakeOp -Encoding ascii -Value @"
@echo off
echo called>"$marker"
echo fake-token
exit /b 0
"@
        Remove-Item Env:DOTFILES_FORCE_SECRET_LOAD -ErrorAction SilentlyContinue

        $loader = $script:secretLoaderPath.Replace("'", "''")
        $fakeOpLiteral = $fakeOp.Replace("'", "''")
        $scriptText = @"
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
exit
"@

        $output = $scriptText | & pwsh -NoLogo -NoProfile

        Test-Path -LiteralPath $marker | Should -BeFalse
        $output | Should -Contain 'gh=False'
        $output | Should -Contain 'githubPat=False'
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

    It 'PowerShell profile の codex wrapper が secret loader 経由で token を読み込むこと' {
        $profilePath = Join-Path $script:chezmoiRoot "shells/Microsoft.PowerShell_profile.ps1"
        $content = Get-Content -LiteralPath $profilePath -Raw

        $content | Should -Match 'GITHUB_PAT_TOKEN' -Because 'GitHub plugin MCP reads GITHUB_PAT_TOKEN from the Codex process environment'
        $content | Should -Match 'DOTFILES_FORCE_SECRET_LOAD' -Because 'Codex should force bounded runtime secret loading before plugin startup'
        $content | Should -Match '\.config\\shell\\secret\.ps1' -Because 'Codex should use the managed PowerShell secret loader'
        $content | Should -Not -Match 'opArgs\s*=\s*@\("run"' -Because 'Codex TUI should not be wrapped in op run because it can break terminal stdout'
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

    It 'WezTerm launcher は既定で GUI 起動時の op run を遅延すること' {
        $content = Get-Content -LiteralPath $script:weztermLaunch -Raw

        $content | Should -Match 'WSLENV=GITHUB_PAT_TOKEN:TAVILY_API_KEY:GITHUB_WORK_TOKEN'
        $content | Should -Not -Match 'WSLENV=GH_TOKEN'
        $content | Should -Match 'WSLENV=.*GITHUB_WORK_TOKEN'
        $content | Should -Match 'DOTFILES_GUI_EAGER_SECRET_LOAD' -Because 'terminal startup should not prompt for 1Password unless explicitly requested'
        $content | Should -Match 'if "%DOTFILES_GUI_EAGER_SECRET_LOAD%"=="1" goto :eager_secret_launch' -Because 'eager GUI secret loading should be opt-in'
        $content | Should -Match '(?s):eager_secret_launch.+op-run-gui-launch\.ps1'
        $content | Should -Match 'DOTFILES_OP_RUN_TIMEOUT_SECONDS'
        $content | Should -Match 'OP_RUN_TIMEOUT_SECONDS=60'
        $content | Should -Match 'wezterm %\*' -Because 'default WezTerm launch should bypass op run'
        $content | Should -Match 'for /f "delims=" %%I in'
        $content | Should -Not -Match 'set "OP_EXE=op"'
    }

    It 'Orca launcher は既定で direct 起動し eager 1Password は opt-in にすること' {
        $content = Get-Content -LiteralPath $script:orcaLaunch -Raw

        $content | Should -Match 'DOTFILES_GUI_EAGER_SECRET_LOAD' -Because 'opening Orca should not prompt for 1Password by default'
        $content | Should -Match 'if "%DOTFILES_GUI_EAGER_SECRET_LOAD%"=="1" goto :eager_secret_launch' -Because 'eager GUI secret loading should remain available as an explicit opt-in'
        $content | Should -Match '(?s):eager_secret_launch.+op-run-gui-launch\.ps1'
        $content | Should -Match 'stop-stale-codex-login\.ps1' -Because 'Orca Codex startup should repair managed account state before opening the UI'
        $content | Should -Match '-AdoptRuntimeCodexAuth' -Because 'Orca should reuse the already-authenticated runtime home instead of repeatedly opening managed login'
        $content | Should -Not -Match '-CleanFailedOrcaHomes' -Because 'deleting managed homes while Orca is running can make CODEX_HOME point at a missing path'
        $content | Should -Not -Match '-Watch' -Because 'background cleanup can race Orca managed login and remove the CODEX_HOME it is about to use'
        $content | Should -Not -Match '-SkipCleanupWhenLoginActive'
        $content | Should -Match 'DOTFILES_CODEX_LOGIN_STALE_AFTER_SECONDS' -Because 'fresh login attempts should be given a grace period before cleanup'
        $content | Should -Match 'PWSH_EXE=%LOCALAPPDATA%\\Microsoft\\WinGet\\Links\\pwsh\.exe' -Because 'Orca data can exceed Windows PowerShell 5.1 JSON parsing compatibility'
        $content | Should -Match 'if exist "%PWSH_EXE%" set "POWERSHELL_EXE=%PWSH_EXE%"' -Because 'startup Codex account adoption should use PowerShell 7 when available'
        $content | Should -Match 'set "ComSpec=%SystemRoot%\\System32\\cmd\.exe"' -Because 'Codex login opens the browser through the Windows shell from Orca child processes'
        $content | Should -Match 'set "PATH=%SystemRoot%\\System32;' -Because 'Orca can launch with a trimmed environment and Codex children need normal Windows tools'
        $content | Should -Match '%USERPROFILE%\\\.local\\bin' -Because 'Orca should resolve the managed codex.cmd wrapper before WinGet codex.exe'
        $content | Should -Match 'DOTFILES_ORCA_LAUNCH=1' -Because 'codex.cmd should only use Orca-specific login short-circuiting for Orca children'
        $content.IndexOf('%USERPROFILE%\.local\bin') | Should -BeLessThan $content.IndexOf('%LOCALAPPDATA%\Microsoft\WinGet\Links') -Because 'codex.cmd must win command resolution inside Orca'
        $content.IndexOf('set "ComSpec=%SystemRoot%\System32\cmd.exe"') | Should -BeLessThan $content.IndexOf('set "ORCA_EXE=') -Because 'environment repair must happen before resolving and launching Orca.exe'
        $content.IndexOf('stop-stale-codex-login.ps1') | Should -BeLessThan $content.IndexOf(':launch_orca') -Because 'managed account repair must run before Orca starts'
        $content | Should -Match 'start "" "%ORCA_EXE%" %\*' -Because 'default Orca launch should bypass op run'
        $content | Should -Match 'DOTFILES_OP_RUN_TIMEOUT_SECONDS' -Because '1Password startup injection should have a bounded wait'
        $content | Should -Match 'OP_RUN_TIMEOUT_SECONDS=60' -Because '1Password can take longer than 20 seconds on the first app auth'
        $content | Should -Match 'PERSONAL_ACCOUNT=EJLA3HRAVZBCXIQ7SRSFGQBTNU' -Because 'personal secrets must resolve against the personal account'
        $content | Should -Match 'WORK_ACCOUNT=aimatecoltd\.1password\.com' -Because 'work secrets must resolve against the company account'
        $content | Should -Match 'Orca\.exe'
        $content | Should -Match 'WinGet\\Links\\op\.exe'
        $content | Should -Match 'secrets\.env'
        $content | Should -Match 'secrets-work\.env'
    }

    It 'Codex CLI launcher が GITHUB_PAT_TOKEN を Codex process に渡すこと' {
        $codexLaunch = Join-Path $script:chezmoiRoot "dot_local/bin/executable_codex.cmd"
        $content = Get-Content -LiteralPath $codexLaunch -Raw

        $content | Should -Match '"%OP_EXE%" run --account "%PERSONAL_ACCOUNT%" --env-file="%PERSONAL_SECRETS_ENV%"' -Because 'personal secrets must resolve against the personal account'
        $content | Should -Match '"%OP_EXE%" run --account "%WORK_ACCOUNT%" --env-file="%WORK_SECRETS_ENV%"' -Because 'work secrets must resolve against the company account'
        $content | Should -Match 'codex\.exe'
        $content | Should -Match 'WinGet\\Packages\\OpenAI\.Codex_\*' -Because 'winget upgrade can leave WinGet Links pointing at the previous portable exe'
        $content | Should -Match 'codex-x86_64-pc-windows-msvc\.exe' -Because 'the current OpenAI.Codex winget package stores the real CLI under this filename'
        $content.IndexOf('WinGet\Packages\OpenAI.Codex_*') | Should -BeLessThan $content.IndexOf('WinGet\Links\codex.exe') -Because 'the package executable should be preferred over a stale Links copy'
        $content | Should -Match 'WinGet\\Links\\op\.exe'
        $content | Should -Match 'GITHUB_PAT_TOKEN'
        $content | Should -Match 'if "%GITHUB_WORK_TOKEN%"=="" set "NEEDS_SECRET_LOAD=1"'
        $content | Should -Match 'if defined NEEDS_SECRET_LOAD if exist "%OP_EXE%"'
        $content | Should -Match 'secrets\.env'
        $content | Should -Match 'secrets-work\.env'
    }

    It 'Codex CLI launcher は login を 1Password env-file injection で包まないこと' {
        $content = Get-Content -LiteralPath $script:codexLaunch -Raw

        $content | Should -Match 'if /i "%~1"=="login" goto :login_codex' -Because 'Codex OAuth/login flows must keep their terminal and browser handshake unwrapped'
        $content.IndexOf('if /i "%~1"=="login" goto :login_codex') | Should -BeLessThan $content.IndexOf('"%OP_EXE%" run --account "%PERSONAL_ACCOUNT%"') -Because 'login must bypass op run before secret injection starts'
    }

    It 'Codex CLI launcher は非 login コマンドを preflight 前に本体へ渡すこと' {
        $content = Get-Content -LiteralPath $script:codexLaunch -Raw
        $fallbackLaunchIndex = $content.IndexOf('goto :launch_codex')
        $loginLabelIndex = $content.IndexOf("`n:login_codex")

        $fallbackLaunchIndex | Should -BeGreaterThan $content.IndexOf('if defined NEEDS_SECRET_LOAD if exist "%OP_EXE%"') -Because 'non-login commands should try secret injection first'
        $fallbackLaunchIndex | Should -BeLessThan $loginLabelIndex -Because 'non-login commands must not fall through into login preflight'
    }

    It 'Codex CLI launcher は login 前に stale OAuth listener を掃除すること' {
        $content = Get-Content -LiteralPath $script:codexLaunch -Raw

        $content | Should -Match 'stop-stale-codex-login\.ps1' -Because 'a previous Codex login can leave the fixed OAuth callback port occupied'
        $content | Should -Match '(?s):login_codex.+stop-stale-codex-login\.ps1.+:launch_codex' -Because 'stale callback listener cleanup must run before starting a new login'
        $content.IndexOf('stop-stale-codex-login.ps1') | Should -BeLessThan $content.LastIndexOf('"%CODEX_EXE%" %*') -Because 'cleanup must happen before Codex opens 127.0.0.1:1457'
    }

    It 'Orca 子プロセスの Codex login は runtime 認証を managed CODEX_HOME に同期して成功扱いにすること' {
        $content = Get-Content -LiteralPath $script:codexLaunch -Raw

        $content | Should -Match 'DOTFILES_ORCA_LAUNCH' -Because 'normal terminal codex login should still use the real OAuth flow'
        $content | Should -Match '-InitializeManagedCodexHomeFromRuntimeAuth' -Because 'Orca managed login should reuse the already-authenticated runtime home'
        $content | Should -Match '(?s)-InitializeManagedCodexHomeFromRuntimeAuth.+exit /b 0.+:launch_codex' -Because 'successful managed home initialization should make Orca addAccount continue without launching another OAuth listener'
    }

    It '1Password env files are split by account' {
        $secretsEnvPath = Join-Path $script:chezmoiRoot "dot_config/shell/secrets.env"
        $workSecretsEnvPath = Join-Path $script:chezmoiRoot "dot_config/shell/secrets-work.env"
        $personalContent = Get-Content -LiteralPath $secretsEnvPath -Raw
        $workContent = Get-Content -LiteralPath $workSecretsEnvPath -Raw

        $personalContent | Should -Match 'GITHUB_PAT_TOKEN=op://Private/GitHubUsedUserPAT/credential'
        $personalContent | Should -Match 'TAVILY_API_KEY=op://Private/TavilyUsedUserPAT/credential'
        $personalContent | Should -Not -Match '^GH_TOKEN=op://Private/GitHubUsedUserPAT/credential'
        $personalContent | Should -Not -Match 'GITHUB_WORK_TOKEN'
        $workContent | Should -Match 'GITHUB_WORK_TOKEN=op://devcontainer/GITHUB_PERSONAL_ACCESS_TOKEN_KOHEI-MIKI-IM8/credential'
        $workContent | Should -Not -Match 'GITHUB_PAT_TOKEN'
    }

    It 'PowerShell secret loader の guard が GITHUB_WORK_TOKEN を含むこと' {
        $secretPs1Path = Join-Path $script:chezmoiRoot "dot_config/shell/secret.ps1"
        $content = Get-Content -LiteralPath $secretPs1Path -Raw

        $content | Should -Match 'GITHUB_PAT_TOKEN'
        $content | Should -Match 'GITHUB_WORK_TOKEN'
        $content | Should -Match 'OP_SERVICE_ACCOUNT_TOKEN'
        $content | Should -Match 'DOTFILES_OP_SERVICE_ACCOUNT_TOKEN_REF'
        $content | Should -Match 'DOTFILES_SECRET_LOAD_ONLY'
        $content | Should -Match '--cache=false'
        $content | Should -Match "'--account'"
        $content | Should -Match "'read'"
        $content | Should -Match 'GitHubUsedUserPAT'
        $content | Should -Match '\$timeoutSeconds = 60'
        $content | Should -Match 'if \(-not \$env:DOTFILES_FORCE_SECRET_LOAD\)\s*\{\s*return\s*\}' -Because 'plain PowerShell profile startup should never call op'
        $content | Should -Not -Match 'GetCommandLineArgs|dotfilesSecretLoadIsCommandMode' -Because 'the guard must not depend on command-mode detection'
    }

    It 'WSL secret loader uses op.exe with cache disabled' {
        $secretShPath = Join-Path $script:chezmoiRoot "dot_config/shell/secret.sh"
        $content = Get-Content -LiteralPath $secretShPath -Raw

        $content | Should -Match 'WSL_DISTRO_NAME'
        $content | Should -Match '_op_cmd=op\.exe'
        $content | Should -Match "_op_cache_arg='--cache=false'"
        $content | Should -Match 'DOTFILES_FORCE_SECRET_LOAD' -Because 'plain shell startup should not ask 1Password for secrets'
        $content | Should -Match '\[ -n "\$\{DOTFILES_FORCE_SECRET_LOAD:-\}" \] \|\| return 0'
        $content | Should -Match 'DOTFILES_SECRET_LOAD_TIMEOUT_SECONDS'
        $content | Should -Match '\bread\b'
        $content | Should -Match 'GitHubUsedUserPAT'
        $content | Should -Match 'GITHUB_PERSONAL_ACCESS_TOKEN_KOHEI-MIKI-IM8'
        $content | Should -Match 'OP_SERVICE_ACCOUNT_TOKEN'
        $content | Should -Match 'DOTFILES_OP_SERVICE_ACCOUNT_TOKEN_REF'
        $content | Should -Match 'DOTFILES_SECRET_LOAD_ONLY'
        $content | Should -Match '--account "\$_acct" read "\$_ref"'
        $content | Should -Not -Match '\binject\b' -Because 'forced shell loading should use bounded individual reads instead of bulk inject'
    }

    It 'bash と zsh の codex wrapper が呼び出し時だけ secret loader を force すること' {
        $bashrc = Get-Content -LiteralPath $script:bashrcPath -Raw
        $commonNix = Get-Content -LiteralPath $script:commonNixPath -Raw

        foreach ($content in @($bashrc, $commonNix)) {
            $content | Should -Match 'codex\(\)' -Because 'codex should be the explicit point where GitHub MCP secrets are loaded'
            $content | Should -Match 'DOTFILES_FORCE_SECRET_LOAD'
            $content | Should -Match '\.config/shell/secret\.sh'
            $content | Should -Match 'command codex "\$@"'
        }
    }

    It 'GUI op run launcher attempts target fallback when 1Password injection times out' {
        $helperPath = Join-Path $script:chezmoiRoot "dot_local/bin/executable_op-run-gui-launch.ps1"
        Test-Path -LiteralPath $helperPath | Should -BeTrue
        (Get-Content -LiteralPath $helperPath -Raw) | Should -Match '\[int\]\$TimeoutSeconds = 60'

        $fakeOp = Join-Path $TestDrive 'op.cmd'
        $personalEnv = Join-Path $TestDrive 'personal.env'
        $workEnv = Join-Path $TestDrive 'work.env'
        $target = Join-Path $TestDrive 'missing-target.exe'

        Set-Content -LiteralPath $personalEnv -Encoding ascii -Value 'GITHUB_PAT_TOKEN=op://Private/token/credential'
        Set-Content -LiteralPath $workEnv -Encoding ascii -Value 'GITHUB_WORK_TOKEN=op://devcontainer/token/credential'
        Set-Content -LiteralPath $fakeOp -Encoding ascii -Value @'
@echo off
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -Command "Start-Sleep -Seconds 6"
exit /b 0
'@

        $output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $helperPath `
            -OpExe $fakeOp `
            -PersonalAccount personal `
            -PersonalEnvFile $personalEnv `
            -WorkAccount work `
            -WorkEnvFile $workEnv `
            -TimeoutSeconds 1 `
            -Target $target 2>&1

        $LASTEXITCODE | Should -Be 1
        ($output -join "`n") | Should -Match '1Password GUI launch injection timed out'
        ($output -join "`n") | Should -Match 'Failed to start GUI target'
    }

    It 'secret loader files are stored at the managed shell config paths' {
        Test-Path -LiteralPath (Join-Path $script:chezmoiRoot "dot_config/shell/secret.ps1") | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:chezmoiRoot "dot_config/shell/secret.sh") | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:chezmoiRoot "dot_config/shell/secrets.env") | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:chezmoiRoot "dot_config/shell/secrets-work.env") | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:chezmoiRoot "secret") | Should -BeFalse
    }
}

Describe 'Codex login preflight helper' {
    BeforeEach {
        Remove-Item Function:\Stop-StaleCodexLoginListener -ErrorAction SilentlyContinue
        Remove-Item Function:\Test-ActiveCodexLoginProcess -ErrorAction SilentlyContinue
        Remove-Item Function:\Test-CodexLoginWatcherAlreadyRunning -ErrorAction SilentlyContinue
        Remove-Item Function:\Adopt-OrcaRuntimeCodexAuthAsManagedAccount -ErrorAction SilentlyContinue
        Remove-Item Function:\Get-OrcaRegisteredCodexAccountIds -ErrorAction SilentlyContinue
        Remove-Item Function:\Remove-FailedOrcaCodexAccountHomes -ErrorAction SilentlyContinue
    }

    It '127.0.0.1:1457 を掴む Codex login process だけ停止すること' {
        Test-Path -LiteralPath $script:codexLoginPreflight | Should -BeTrue
        . $script:codexLoginPreflight

        Mock Get-NetTCPConnection {
            @(
                [pscustomobject]@{ OwningProcess = 1111 }
                [pscustomobject]@{ OwningProcess = 2222 }
                [pscustomobject]@{ OwningProcess = 3333 }
                [pscustomobject]@{ OwningProcess = 4444 }
            )
        }
        Mock Get-CimInstance {
            param(
                [string]$ClassName,
                [string]$Filter
            )

            $null = $ClassName

            switch -Regex ($Filter) {
                '1111' {
                    [pscustomobject]@{
                        Name           = 'codex.exe'
                        ExecutablePath = 'C:\Users\KoheiMiki\AppData\Local\Microsoft\WinGet\Links\codex.exe'
                        CommandLine    = 'C:\Users\KoheiMiki\AppData\Local\Microsoft\WinGet\Links\codex.exe login'
                    }
                }
                '2222' {
                    [pscustomobject]@{
                        Name           = 'codex.exe'
                        ExecutablePath = 'C:\Users\KoheiMiki\AppData\Local\Microsoft\WinGet\Links\codex.exe'
                        CommandLine    = 'C:\Users\KoheiMiki\AppData\Local\Microsoft\WinGet\Links\codex.exe app-server'
                    }
                }
                '3333' {
                    [pscustomobject]@{
                        Name           = 'other.exe'
                        ExecutablePath = 'C:\Tools\other.exe'
                        CommandLine    = 'other.exe login'
                    }
                }
                '4444' {
                    [pscustomobject]@{
                        Name           = 'codex-x86_64-pc-windows-msvc.exe'
                        ExecutablePath = 'C:\Users\KoheiMiki\AppData\Local\Microsoft\WinGet\Packages\OpenAI.Codex_Microsoft.Winget.Source_8wekyb3d8bbwe\codex-x86_64-pc-windows-msvc.exe'
                        CommandLine    = 'C:\Users\KoheiMiki\AppData\Local\Microsoft\WinGet\Packages\OpenAI.Codex_Microsoft.Winget.Source_8wekyb3d8bbwe\codex-x86_64-pc-windows-msvc.exe login'
                    }
                }
            }
        }
        Mock Stop-Process { }
        Mock Write-Host { }
        Mock Write-Warning { }

        Stop-StaleCodexLoginListener

        Should -Invoke Get-NetTCPConnection -Times 1 -Exactly -ParameterFilter {
            $LocalAddress -eq '127.0.0.1' -and $LocalPort -eq 1457 -and $State -eq 'Listen'
        }
        Should -Invoke Stop-Process -Times 1 -Exactly -ParameterFilter {
            $Id -eq 1111 -and $Force
        }
        Should -Invoke Stop-Process -Times 1 -Exactly -ParameterFilter {
            $Id -eq 4444 -and $Force
        }
        Should -Invoke Stop-Process -Times 0 -Exactly -ParameterFilter {
            $Id -in @(2222, 3333)
        }
    }

    It 'stale threshold 未満の codex.exe login listener は停止しないこと' {
        Test-Path -LiteralPath $script:codexLoginPreflight | Should -BeTrue
        . $script:codexLoginPreflight

        Mock Get-Date {
            [datetime]'2026-07-10T12:00:00'
        }
        Mock Get-NetTCPConnection {
            @(
                [pscustomobject]@{ OwningProcess = 1111 }
                [pscustomobject]@{ OwningProcess = 2222 }
            )
        }
        Mock Get-CimInstance {
            param(
                [string]$ClassName,
                [string]$Filter
            )

            $null = $ClassName

            switch -Regex ($Filter) {
                '1111' {
                    [pscustomobject]@{
                        Name           = 'codex.exe'
                        ExecutablePath = 'C:\Users\KoheiMiki\AppData\Local\Microsoft\WinGet\Links\codex.exe'
                        CommandLine    = 'C:\Users\KoheiMiki\AppData\Local\Microsoft\WinGet\Links\codex.exe login'
                        CreationDate   = [datetime]'2026-07-10T11:59:30'
                    }
                }
                '2222' {
                    [pscustomobject]@{
                        Name           = 'codex.exe'
                        ExecutablePath = 'C:\Users\KoheiMiki\AppData\Local\Microsoft\WinGet\Links\codex.exe'
                        CommandLine    = 'C:\Users\KoheiMiki\AppData\Local\Microsoft\WinGet\Links\codex.exe login'
                        CreationDate   = [datetime]'2026-07-10T11:50:00'
                    }
                }
            }
        }
        Mock Stop-Process { }
        Mock Write-Host { }
        Mock Write-Warning { }

        Stop-StaleCodexLoginListener -StaleAfterSeconds 120

        Should -Invoke Stop-Process -Times 0 -Exactly -ParameterFilter {
            $Id -eq 1111
        }
        Should -Invoke Stop-Process -Times 1 -Exactly -ParameterFilter {
            $Id -eq 2222 -and $Force
        }
    }

    It '既存の Orca Codex login watcher process を検出すること' {
        Test-Path -LiteralPath $script:codexLoginPreflight | Should -BeTrue
        . $script:codexLoginPreflight

        Mock Get-CimInstance {
            param(
                [string]$ClassName,
                [string]$Filter
            )

            $null = $ClassName
            $null = $Filter

            @(
                [pscustomobject]@{
                    ProcessId   = $PID
                    CommandLine = 'powershell.exe -NoProfile -File C:\Users\KoheiMiki\.local\bin\stop-stale-codex-login.ps1 -CleanFailedOrcaHomes -Watch'
                }
                [pscustomobject]@{
                    ProcessId   = 9999
                    CommandLine = 'powershell.exe -NoProfile -File C:\Users\KoheiMiki\.local\bin\stop-stale-codex-login.ps1 -CleanFailedOrcaHomes -Watch'
                }
                [pscustomobject]@{
                    ProcessId   = 8888
                    CommandLine = 'powershell.exe -Command "stop-stale-codex-login.ps1 -Watch"'
                }
            )
        }

        Test-CodexLoginWatcherAlreadyRunning | Should -BeTrue

        Should -Invoke Get-CimInstance -Times 1 -Exactly -ParameterFilter {
            $ClassName -eq 'Win32_Process' -and $Filter -match 'powershell'
        }
    }

    It 'runtime home の Codex auth.json を Orca managed account として採用すること' {
        Test-Path -LiteralPath $script:codexLoginPreflight | Should -BeTrue
        . $script:codexLoginPreflight

        function New-TestJwt([hashtable]$Payload) {
            $json = $Payload | ConvertTo-Json -Depth 10 -Compress
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
            $payloadPart = [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
            return "test-header.$payloadPart.test-signature"
        }

        $orcaRoot = Join-Path $TestDrive 'orca-adopt-runtime'
        $runtimeHome = Join-Path $orcaRoot 'codex-runtime-home\home'
        New-Item -ItemType Directory -Path $runtimeHome -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $runtimeHome 'config.toml') -Encoding ascii -Value 'model = "gpt-5.5"'
        Set-Content -LiteralPath (Join-Path $runtimeHome 'hooks.json') -Encoding ascii -Value '{}'
        Set-Content -LiteralPath (Join-Path $runtimeHome 'auth.json') -Encoding ascii -Value (@{
                auth_mode = 'chatgpt'
                OPENAI_API_KEY = $null
                tokens = @{
                    id_token = New-TestJwt @{
                        email = 'kohei@example.com'
                        'https://api.openai.com/auth' = @{
                            chatgpt_account_id = 'acct_123'
                            workspace_name = 'ai-mate'
                            workspace_account_id = 'ws_456'
                        }
                    }
                    access_token = 'test-access-token'
                    refresh_token = 'test-refresh-token'
                    account_id = 'acct_123'
                }
                last_refresh = '2026-07-10T00:00:00Z'
            } | ConvertTo-Json -Depth 10)
        Set-Content -LiteralPath (Join-Path $orcaRoot 'orca-data.json') -Encoding ascii -Value (@{
                settings = @{
                    codexManagedAccounts = @()
                    activeCodexManagedAccountId = $null
                    activeCodexManagedAccountIdsByRuntime = @{
                        host = $null
                        wsl = @{}
                    }
                }
            } | ConvertTo-Json -Depth 10)

        Adopt-OrcaRuntimeCodexAuthAsManagedAccount -OrcaDataRoot $orcaRoot | Should -BeTrue
        Adopt-OrcaRuntimeCodexAuthAsManagedAccount -OrcaDataRoot $orcaRoot | Should -BeTrue

        $data = Get-Content -LiteralPath (Join-Path $orcaRoot 'orca-data.json') -Raw | ConvertFrom-Json
        $accounts = @($data.settings.codexManagedAccounts)
        $accounts.Count | Should -Be 1
        $account = $accounts[0]
        $account.email | Should -Be 'kohei@example.com'
        $account.providerAccountId | Should -Be 'acct_123'
        $account.workspaceLabel | Should -Be 'ai-mate'
        $account.workspaceAccountId | Should -Be 'ws_456'
        $account.managedHomeRuntime | Should -Be 'host'
        $data.settings.activeCodexManagedAccountId | Should -Be $account.id
        $data.settings.activeCodexManagedAccountIdsByRuntime.host | Should -Be $account.id

        Test-Path -LiteralPath (Join-Path $account.managedHomePath 'auth.json') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $account.managedHomePath 'config.toml') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $account.managedHomePath 'hooks.json') | Should -BeTrue
        (Get-Content -LiteralPath (Join-Path $account.managedHomePath '.orca-managed-home') -Raw).Trim() | Should -Be $account.id
    }

    It 'Orca managed CODEX_HOME に runtime home の Codex auth を初期化すること' {
        Test-Path -LiteralPath $script:codexLoginPreflight | Should -BeTrue
        . $script:codexLoginPreflight

        function New-TestJwt([hashtable]$Payload) {
            $json = $Payload | ConvertTo-Json -Depth 10 -Compress
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
            $payloadPart = [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
            return "test-header.$payloadPart.test-signature"
        }

        $orcaRoot = Join-Path $TestDrive 'orca-initialize-managed-home'
        $runtimeHome = Join-Path $orcaRoot 'codex-runtime-home\home'
        $accountId = '11111111-1111-1111-1111-111111111111'
        $managedHome = Join-Path $orcaRoot "codex-accounts\$accountId\home"
        New-Item -ItemType Directory -Path $runtimeHome -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $runtimeHome 'config.toml') -Encoding ascii -Value 'model = "gpt-5.5"'
        Set-Content -LiteralPath (Join-Path $runtimeHome 'auth.json') -Encoding ascii -Value (@{
                auth_mode = 'chatgpt'
                tokens = @{
                    id_token = New-TestJwt @{
                        email = 'kohei@example.com'
                    }
                }
            } | ConvertTo-Json -Depth 5)

        Initialize-OrcaManagedCodexHomeFromRuntimeAuth -OrcaDataRoot $orcaRoot -ManagedHomePath $managedHome | Should -BeTrue

        Test-Path -LiteralPath (Join-Path $managedHome 'auth.json') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $managedHome 'config.toml') | Should -BeTrue
        (Get-Content -LiteralPath (Join-Path $managedHome '.orca-managed-home') -Raw).Trim() | Should -Be $accountId
    }

    It 'Orca 管理外の CODEX_HOME は runtime auth 初期化対象にしないこと' {
        Test-Path -LiteralPath $script:codexLoginPreflight | Should -BeTrue
        . $script:codexLoginPreflight

        $orcaRoot = Join-Path $TestDrive 'orca-reject-non-managed-home'
        $runtimeHome = Join-Path $orcaRoot 'codex-runtime-home\home'
        $outsideHome = Join-Path $TestDrive 'plain-codex-home'
        New-Item -ItemType Directory -Path $runtimeHome -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $runtimeHome 'auth.json') -Encoding ascii -Value '{}'

        Initialize-OrcaManagedCodexHomeFromRuntimeAuth -OrcaDataRoot $orcaRoot -ManagedHomePath $outsideHome | Should -BeFalse

        Test-Path -LiteralPath (Join-Path $outsideHome 'auth.json') | Should -BeFalse
    }

    It '未登録で auth.json のない Orca Codex account home だけ削除すること' {
        Test-Path -LiteralPath $script:codexLoginPreflight | Should -BeTrue
        . $script:codexLoginPreflight

        $orcaRoot = Join-Path $TestDrive 'orca-cleanup-selection'
        $accountRoot = Join-Path $orcaRoot 'codex-accounts'
        $failedId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
        $registeredId = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
        $authenticatedId = 'cccccccc-cccc-cccc-cccc-cccccccccccc'
        $initializedOrphanId = 'abababab-abab-abab-abab-abababababab'
        $nonGuidId = 'not-a-guid'

        New-Item -ItemType Directory -Path (Join-Path $accountRoot "$failedId\home\log") -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $accountRoot "$failedId\home\tmp") -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $accountRoot "$registeredId\home\log") -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $accountRoot "$authenticatedId\home") -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $accountRoot "$initializedOrphanId\home") -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $accountRoot "$nonGuidId\home\log") -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $accountRoot "$authenticatedId\home\auth.json") -Encoding ascii -Value '{}'
        Set-Content -LiteralPath (Join-Path $accountRoot "$initializedOrphanId\home\auth.json") -Encoding ascii -Value '{}'
        Set-Content -LiteralPath (Join-Path $accountRoot "$initializedOrphanId\home\.orca-managed-home") -Encoding ascii -Value $initializedOrphanId
        Set-Content -LiteralPath (Join-Path $orcaRoot 'orca-data.json') -Encoding ascii -Value (@{
                settings = @{
                    codexManagedAccounts = @(
                        @{
                            id = $registeredId
                        }
                    )
                }
            } | ConvertTo-Json -Depth 5)

        Remove-FailedOrcaCodexAccountHomes -OrcaDataRoot $orcaRoot

        Test-Path -LiteralPath (Join-Path $accountRoot $failedId) | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $accountRoot $registeredId) | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $accountRoot $authenticatedId) | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $accountRoot $initializedOrphanId) | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $accountRoot $nonGuidId) | Should -BeTrue
    }

    It 'active な codex login がある間は Orca Codex account home cleanup を延期すること' {
        Test-Path -LiteralPath $script:codexLoginPreflight | Should -BeTrue
        . $script:codexLoginPreflight

        $orcaRoot = Join-Path $TestDrive 'orca-active-login'
        $accountRoot = Join-Path $orcaRoot 'codex-accounts'
        $failedId = 'ffffffff-ffff-ffff-ffff-ffffffffffff'
        New-Item -ItemType Directory -Path (Join-Path $accountRoot "$failedId\home\log") -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $orcaRoot 'orca-data.json') -Encoding ascii -Value '{"settings":{"codexManagedAccounts":[]}}'

        Mock Get-Date {
            [datetime]'2026-07-10T12:00:00'
        }
        Mock Get-CimInstance {
            param(
                [string]$ClassName,
                [string]$Filter
            )

            if ($ClassName -eq 'Win32_Process' -and $Filter -eq "Name = 'codex.exe'") {
                return @(
                    [pscustomobject]@{
                        Name           = 'codex.exe'
                        ExecutablePath = 'C:\Users\KoheiMiki\AppData\Local\Microsoft\WinGet\Links\codex.exe'
                        CommandLine    = 'C:\Users\KoheiMiki\AppData\Local\Microsoft\WinGet\Links\codex.exe login'
                        CreationDate   = [datetime]'2026-07-10T11:59:30'
                    }
                )
            }

            return @()
        }
        Mock Write-Warning { }

        Remove-FailedOrcaCodexAccountHomes -OrcaDataRoot $orcaRoot -SkipWhenCodexLoginActive -StaleAfterSeconds 120

        Test-Path -LiteralPath (Join-Path $accountRoot $failedId) | Should -BeTrue
    }

    It 'orca-data.json 全体の JSON parse に失敗しても登録済み Codex account は削除しないこと' {
        Test-Path -LiteralPath $script:codexLoginPreflight | Should -BeTrue
        . $script:codexLoginPreflight

        $orcaRoot = Join-Path $TestDrive 'orca-json-fallback'
        $accountRoot = Join-Path $orcaRoot 'codex-accounts'
        $registeredId = 'dddddddd-dddd-dddd-dddd-dddddddddddd'
        $failedId = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'

        New-Item -ItemType Directory -Path (Join-Path $accountRoot "$registeredId\home\log") -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $accountRoot "$failedId\home\log") -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $orcaRoot 'orca-data.json') -Encoding ascii -Value @"
{
  "settings": {
    "codexManagedAccounts": [
      {
        "id": "$registeredId"
      }
    ],
    "activeCodexManagedAccountId": "$registeredId"
  },
  "otherState": {
    "shapeThatOldPowerShellCannotParse": true
  }
}
"@
        Mock ConvertFrom-Json {
            throw 'PowerShell 5.1 JSON parser failed'
        }

        Remove-FailedOrcaCodexAccountHomes -OrcaDataRoot $orcaRoot

        Test-Path -LiteralPath (Join-Path $accountRoot $registeredId) | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $accountRoot $failedId) | Should -BeFalse
    }
}
