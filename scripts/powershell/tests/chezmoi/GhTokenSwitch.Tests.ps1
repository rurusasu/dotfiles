#Requires -Module Pester

BeforeAll {
    $script:repoRoot = Join-Path $PSScriptRoot "../../../../"
    $script:chezmoiRoot = Join-Path $script:repoRoot "chezmoi"
    $script:helperPath = Join-Path $script:chezmoiRoot "dot_config/shell/gh-token-switch.ps1"
    $script:weztermLaunch = Join-Path $script:chezmoiRoot "secret/wezterm-launch.cmd"
}

AfterAll {
    Remove-Item Function:\gh -ErrorAction SilentlyContinue
    Remove-Item Function:\Invoke-DotfilesGitHubCli -ErrorAction SilentlyContinue
    Remove-Item Function:\Resolve-DotfilesGitHubCli -ErrorAction SilentlyContinue
    Remove-Item Function:\Test-DotfilesWorkGitHubRepository -ErrorAction SilentlyContinue
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

        $content | Should -Match 'WSLENV=.*GITHUB_WORK_TOKEN'
    }

    It 'secrets.env が work token の 1Password 参照を含むこと' {
        $secretsEnvPath = Join-Path $script:chezmoiRoot "secret/secrets.env"
        $content = Get-Content -LiteralPath $secretsEnvPath -Raw

        $content | Should -Match 'GITHUB_WORK_TOKEN=op://devcontainer/GITHUB_PERSONAL_ACCESS_TOKEN_KOHEI-MIKI-IM8/credential'
    }

    It 'PowerShell secret loader の guard が GITHUB_WORK_TOKEN を含むこと' {
        $secretPs1Path = Join-Path $script:chezmoiRoot "secret/env.ps1"
        $content = Get-Content -LiteralPath $secretPs1Path -Raw

        $content | Should -Match 'GITHUB_WORK_TOKEN'
    }
}
