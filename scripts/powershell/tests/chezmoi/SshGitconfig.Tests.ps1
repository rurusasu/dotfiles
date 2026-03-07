#Requires -Module Pester

<#
.SYNOPSIS
    SSH 設定と gitconfig テンプレートのバリデーションテスト

.DESCRIPTION
    PC 再起動後も git push / commit sign が動作するための必須条件を検証:
    - SSH config テンプレートに 1Password agent 設定が含まれること
    - gitconfig テンプレートに op-ssh-sign が設定されていること
    - SSH deploy スクリプトがテンプレートをインライン展開していること
    - 公開鍵参照がすべてデプロイ可能であること
#>

BeforeAll {
    $script:chezmoiRoot = Join-Path $PSScriptRoot "../../../../chezmoi"
    $script:sshConfigTmpl = Join-Path $script:chezmoiRoot "ssh/config.tmpl"
    $script:gitconfigTmpl = Join-Path $script:chezmoiRoot "create_dot_gitconfig.tmpl"
    $script:sshDeployPs1 = Join-Path $script:chezmoiRoot ".chezmoiscripts/deploy/ssh/run_onchange_deploy.ps1.tmpl"
    $script:sshDeploySh = Join-Path $script:chezmoiRoot ".chezmoiscripts/deploy/ssh/run_onchange_deploy.sh.tmpl"
    $script:chezmoiToml = Join-Path $script:chezmoiRoot ".chezmoi.toml.tmpl"
}

Describe 'SSH config テンプレート' {
    BeforeAll {
        $script:sshContent = Get-Content -Path $script:sshConfigTmpl -Raw
    }

    It '1Password SSH Agent の IdentityAgent が Windows 用に設定されていること' {
        $script:sshContent | Should -Match 'openssh-ssh-agent' -Because "Windows では 1Password が //./pipe/openssh-ssh-agent を使用する"
    }

    It '1Password SSH Agent の IdentityAgent が macOS 用に設定されていること' {
        $script:sshContent | Should -Match '2BUA8C4S2C\.com\.1password' -Because "macOS では 1Password Group Container のソケットを使用する"
    }

    It '1Password SSH Agent の IdentityAgent が Linux 用に設定されていること' {
        $script:sshContent | Should -Match '\.1password/agent\.sock' -Because "Linux では ~/.1password/agent.sock を使用する"
    }

    It 'github.com ホストが signing_key.pub を IdentityFile に指定していること' {
        $script:sshContent | Should -Match 'IdentityFile.*signing_key\.pub'
    }

    It 'IdentitiesOnly yes が設定されていること' {
        $script:sshContent | Should -Match 'IdentitiesOnly\s+yes' -Because "エージェントに不要な鍵を提示させないため"
    }

    It 'デプロイされない公開鍵を参照していないこと' {
        $identityFiles = [regex]::Matches($script:sshContent, 'IdentityFile\s+(.+)') |
            ForEach-Object { $_.Groups[1].Value.Trim() }

        $deployedKeys = @('~/.ssh/signing_key.pub')
        foreach ($keyPath in $identityFiles) {
            $keyPath | Should -BeIn $deployedKeys -Because "参照される公開鍵はすべて deploy スクリプトでデプロイされる必要がある"
        }
    }
}

Describe 'gitconfig テンプレート' {
    BeforeAll {
        $script:gitconfigContent = Get-Content -Path $script:gitconfigTmpl -Raw
    }

    It 'gpg.format が ssh に設定されていること' {
        $script:gitconfigContent | Should -Match 'format\s*=\s*ssh'
    }

    It 'commit.gpgsign が true に設定されていること' {
        $script:gitconfigContent | Should -Match 'gpgsign\s*=\s*true'
    }

    It 'Windows 用に op-ssh-sign.exe が gpg.ssh.program に設定されていること' {
        $script:gitconfigContent | Should -Match 'op-ssh-sign\.exe' -Because "1Password で署名するには op-ssh-sign が必要"
    }

    It 'macOS 用に op-ssh-sign が gpg.ssh.program に設定されていること' {
        $script:gitconfigContent | Should -Match '/Applications/1Password.*op-ssh-sign'
    }

    It 'Linux 用に op-ssh-sign が gpg.ssh.program に設定されていること' {
        $script:gitconfigContent | Should -Match '/opt/1Password/op-ssh-sign'
    }

    It 'ssh-keygen を gpg.ssh.program に使用していないこと' {
        $script:gitconfigContent | Should -Not -Match 'program\s*=.*ssh-keygen' -Because "ssh-keygen は 1Password の鍵にアクセスできない"
    }

    It 'OS 別の分岐がすべてのプラットフォームをカバーしていること' {
        $script:gitconfigContent | Should -Match 'eq \.chezmoi\.os "windows"'
        $script:gitconfigContent | Should -Match 'eq \.chezmoi\.os "darwin"'
    }
}

Describe 'SSH deploy スクリプト' {
    Context 'Windows (ps1.tmpl)' {
        BeforeAll {
            $script:ps1Content = Get-Content -Path $script:sshDeployPs1 -Raw
        }

        It 'ssh/config.tmpl を include でインライン展開していること' {
            $script:ps1Content | Should -Match 'include "ssh/config\.tmpl"' -Because "テンプレートファイルを直接コピーすると未展開のまま配置される"
        }

        It 'config.tmpl のハッシュが変更検出に使われていること' {
            $script:ps1Content | Should -Match 'hash:.*include "ssh/config\.tmpl".*sha256sum'
        }

        It 'ファイルコピー (Deploy-File) ではなくコンテンツ展開 (Deploy-Content) を使用していること' {
            $script:ps1Content | Should -Not -Match 'Deploy-File.*ssh.config' -Because "テンプレートファイルのパスでコピーすると存在しないファイルを参照する"
            $script:ps1Content | Should -Match 'Deploy-Content.*\\\.ssh\\config'
        }

        It 'onepasswordRead が lookPath "op" でガードされていること' {
            $lines = Get-Content -Path $script:sshDeployPs1
            $inOpGuard = $false
            $violations = @()
            $lineNum = 0

            foreach ($line in $lines) {
                $lineNum++
                if ($line -match '\{\{-?\s*if\s+lookPath\s+"op"') { $inOpGuard = $true }
                if ($line -match 'onepasswordRead' -and -not $inOpGuard -and $line -notmatch '^\s*#') {
                    $violations += "line $lineNum"
                }
                if ($line -match '\{\{-?\s*end\s*\}\}' -and $inOpGuard) { $inOpGuard = $false }
            }
            $violations | Should -BeNullOrEmpty
        }
    }

    Context 'Linux/macOS (sh.tmpl)' {
        BeforeAll {
            $script:shContent = Get-Content -Path $script:sshDeploySh -Raw
        }

        It 'ssh/config.tmpl を include でインライン展開していること' {
            $script:shContent | Should -Match 'include "ssh/config\.tmpl"' -Because "テンプレートファイルを直接コピーすると未展開のまま配置される"
        }

        It 'SSH config のパーミッションを 600 に設定していること' {
            $script:shContent | Should -Match 'chmod 600.*\.ssh/config' -Because "SSH config は所有者のみ読み書き可能にする必要がある"
        }

        It 'onepasswordRead が lookPath "op" でガードされていること' {
            $lines = Get-Content -Path $script:sshDeploySh
            $inOpGuard = $false
            $violations = @()
            $lineNum = 0

            foreach ($line in $lines) {
                $lineNum++
                if ($line -match '\{\{-?\s*if\s+lookPath\s+"op"') { $inOpGuard = $true }
                if ($line -match 'onepasswordRead' -and -not $inOpGuard -and $line -notmatch '^\s*#') {
                    $violations += "line $lineNum"
                }
                if ($line -match '\{\{-?\s*end\s*\}\}' -and $inOpGuard) { $inOpGuard = $false }
            }
            $violations | Should -BeNullOrEmpty
        }
    }
}

Describe 'chezmoi.toml テンプレート' {
    BeforeAll {
        $script:tomlContent = Get-Content -Path $script:chezmoiToml -Raw
    }

    It 'git.name の promptStringOnce が設定されていること' {
        $script:tomlContent | Should -Match 'promptStringOnce.*git\.name'
    }

    It 'git.email の promptStringOnce が設定されていること' {
        $script:tomlContent | Should -Match 'promptStringOnce.*git\.email'
    }

    It 'git.signingkey のデフォルト値が signing_key.pub であること' {
        $script:tomlContent | Should -Match 'signing_key\.pub'
    }
}
