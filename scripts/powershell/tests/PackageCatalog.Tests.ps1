#Requires -Module Pester

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    $script:winget = Get-Content -LiteralPath (Join-Path $script:repoRoot 'windows/winget/packages.json') -Raw | ConvertFrom-Json
    $script:packages = @($script:winget.Sources | ForEach-Object { $_.Packages })
}

Describe 'Windows GUI-only package catalog' {
    It 'should install exactly the selected GUI apps and no CLI or desktop automation packages' {
        $expected = @(
            'AgileBits.1Password', 'Discord.Discord', 'Google.Chrome',
            'Microsoft.PowerToys', 'Microsoft.WindowsTerminal', 'Obsidian.Obsidian',
            'StablyAI.Orca', 'TheBrowserCompany.Arc', 'wez.wezterm', '9PLM9XGG6VKS'
        )
        (@($script:packages.PackageIdentifier | Sort-Object) -join '|') |
            Should -Be (($expected | Sort-Object) -join '|')
    }

    It 'should generate empty npm and pnpm manifests' {
        foreach ($manager in 'npm', 'pnpm') {
            $manifest = Get-Content -LiteralPath (Join-Path $script:repoRoot "windows/$manager/packages.json") -Raw | ConvertFrom-Json
            @($manifest.globalPackages).Count | Should -Be 0
        }
    }

    It 'should retain unique package identities and source-specific verifiers' {
        $script:packages.Count | Should -BeGreaterThan 0
        @($script:packages.PackageIdentifier | Select-Object -Unique).Count | Should -Be $script:packages.Count
        foreach ($package in $script:packages) {
            $package.verifyCommand | Should -Not -BeNullOrEmpty
            $package.verifyCommand.command | Should -Not -BeNullOrEmpty
            $package.PSObject.Properties.Name | Should -Not -Contain 'Version'
            $package.installTimeoutSeconds | Should -Be 3600
        }
        @($script:packages | Where-Object requiresAdmin).Count | Should -Be 0
        (@($script:packages | Where-Object ciSkipInstall | ForEach-Object PackageIdentifier | Sort-Object) -join '|') |
            Should -Be '9PLM9XGG6VKS|StablyAI.Orca'
    }

    It 'should keep WezTerm stable and use its declared executable directory' {
        $package = $script:packages | Where-Object PackageIdentifier -EQ 'wez.wezterm'
        @($package.pathEntries) | Should -Contain '%ProgramFiles%\WezTerm'
        $package.verifyCommand.command | Should -Be 'wezterm'
        @($package.verifyCommand.args) | Should -Be @('--version')
        @($package.installArgs) | Should -Not -Contain '--ignore-security-hash'
        $package.PSObject.Properties.Name | Should -Not -Contain 'skipInstall'
        $package.PSObject.Properties.Name | Should -Not -Contain 'ciSkipInstall'
    }

    It 'should verify <Id> by its AppX launch identity without launching the GUI' -ForEach @(
        @{ Id = 'TheBrowserCompany.Arc'; Command = 'TheBrowserCompany.Arc'; Target = 'TheBrowserCompany.Arc_ttt1ap7aakyb4!Arc' }
        @{ Id = 'Microsoft.WindowsTerminal'; Command = 'Microsoft.WindowsTerminal'; Target = 'Microsoft.WindowsTerminal_8wekyb3d8bbwe!App' }
        @{ Id = '9PLM9XGG6VKS'; Command = 'OpenAI.Codex'; Target = 'OpenAI.Codex_2p2nqsd0c76g0!App' }
    ) {
        $package = $script:packages | Where-Object PackageIdentifier -EQ $Id
        $package.verifyCommand.type | Should -Be 'appxLaunchTarget'
        $package.verifyCommand.command | Should -Be $Command
        @($package.verifyCommand.args) | Should -Be @($Target)
    }

    It 'should verify <Id> using an installed-product identity' -ForEach @(
        @{ Id = 'AgileBits.1Password'; Command = 'AgileBits.1Password' }
        @{ Id = 'Discord.Discord'; Command = 'Discord' }
        @{ Id = 'Google.Chrome'; Command = 'Google Chrome' }
        @{ Id = 'Obsidian.Obsidian'; Command = 'Obsidian' }
        @{ Id = 'StablyAI.Orca'; Command = 'OrcaSlicer' }
        @{ Id = 'Microsoft.PowerToys'; Command = 'Microsoft PowerToys' }
    ) {
        $package = $script:packages | Where-Object PackageIdentifier -EQ $Id
        $package.verifyCommand.type | Should -Be 'windowsInstalledProduct'
        $package.verifyCommand.command | Should -Be $Command
        $package.verifyCommand.uninstallEntry | Should -Not -BeNullOrEmpty
    }

    It 'should recognize user-installed PowerToys without launching it' {
        $entry = ($script:packages | Where-Object PackageIdentifier -EQ 'Microsoft.PowerToys').verifyCommand.uninstallEntry
        'PowerToys' | Should -Match $entry.displayNamePattern
        'PowerToys (Preview)' | Should -Match $entry.displayNamePattern
        'Microsoft PowerToys Preview' | Should -Not -Match $entry.displayNamePattern
        $entry.publisher | Should -Be 'Microsoft Corporation'
        @($entry.executablePaths) | Should -Contain '%LOCALAPPDATA%\PowerToys\PowerToys.exe'
    }

    It 'should retain the 1Password GUI executable identity independently of its CLI' {
        $verify = ($script:packages | Where-Object PackageIdentifier -EQ 'AgileBits.1Password').verifyCommand
        $verify.appxPackage.packageFamilyName | Should -Be 'Agilebits.1Password_amwd9z03whsfe'
        $verify.appxPackage.executable | Should -Be '1Password.exe'
        @($verify.uninstallEntry.executablePaths).Count | Should -BeGreaterThan 0
    }

    It 'should not retire the active desktop app' {
        $retired = Get-Content -LiteralPath (Join-Path $script:repoRoot 'windows/winget/retired-packages.json') -Raw | ConvertFrom-Json
        @($retired.packages | Where-Object id -EQ '9PLM9XGG6VKS').Count | Should -Be 0
    }

    It 'should update flake inputs before every scripted NixOS rebuild entry point' {
        $taskfile = Get-Content -LiteralPath (Join-Path $script:repoRoot "taskfiles/nix/taskfile.yml") -Raw
        $updateScript = Get-Content -LiteralPath (Join-Path $script:repoRoot "scripts/sh/update.sh") -Raw
        $postInstallScript = Get-Content -LiteralPath (Join-Path $script:repoRoot "scripts/sh/nixos-wsl-postinstall.sh") -Raw
        $commonInstallScript = Get-Content -LiteralPath (Join-Path $script:repoRoot "scripts/sh/install-common.sh") -Raw

        $taskfile | Should -Match 'nix flake update && scripts/sh/nixos-rebuild-with-user\.sh switch --flake \. --impure'
        $updateScript | Should -Match 'nix flake update --flake ~/.dotfiles'
        $commonInstallScript | Should -Match 'nix flake update --flake "\$flake_ref"'
        $postInstallScript | Should -Match 'dotfiles_update_flake "\$TARGET_DIR" path'
        $commonInstallScript | Should -Not -Match 'dotfiles_trust_git_directory|git config --global'
        $postInstallScript | Should -Not -Match 'git config --global'
    }
}
