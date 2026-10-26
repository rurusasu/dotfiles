#Requires -Module Pester

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    $script:winget = Get-Content -LiteralPath (Join-Path $script:repoRoot 'windows/winget/packages.json') -Raw | ConvertFrom-Json
    $script:packages = @($script:winget.Sources | ForEach-Object { $_.Packages })
}

Describe 'Windows application and setup-tool package catalog' {
    It 'should install exactly Windows setup components and retained interop apps' {
        $expected = @(
            'AgileBits.1Password', 'Discord.Discord',
            'Microsoft.PowerToys', 'Microsoft.PowerShell', 'Microsoft.WindowsTerminal', 'Task.Task', 'twpayne.chezmoi',
            'StablyAI.Orca', 'wez.wezterm', 'yorukot.superfile', '9PLM9XGG6VKS', '9PCFS5B6T72H', 'TheBrowserCompany.Dia', 'Starship.Starship', 'Git.MinGit'
        )
        (@($script:packages.PackageIdentifier | Sort-Object) -join '|') |
            Should -Be (($expected | Sort-Object) -join '|')
    }

    It 'should include unpinned stable PowerShell with the pwsh verifier' {
        @($script:packages | Where-Object PackageIdentifier -EQ 'Microsoft.PowerShell').Count | Should -Be 1
        $powershell = $script:packages | Where-Object PackageIdentifier -EQ 'Microsoft.PowerShell'
        $powershell.verifyCommand.command | Should -Be 'pwsh'
        @($powershell.verifyCommand.args) | Should -Be @('--version')
        $powershell.PSObject.Properties.Name | Should -Not -Contain 'Version'
    }

    It 'should install chezmoi from WinGet and verify its command' {
        $chezmoi = $script:packages | Where-Object PackageIdentifier -EQ 'twpayne.chezmoi'
        @($chezmoi).Count | Should -Be 1
        $chezmoi.verifyCommand.command | Should -Be 'chezmoi'
        @($chezmoi.verifyCommand.args) | Should -Be @('--version')
        $chezmoi.installTimeoutSeconds | Should -Be 3600
    }

    It 'should generate empty npm and pnpm manifests' {
        foreach ($manager in 'npm', 'pnpm') {
            $manifest = Get-Content -LiteralPath (Join-Path $script:repoRoot "windows/$manager/packages.json") -Raw | ConvertFrom-Json
            @($manifest.globalPackages).Count | Should -Be 0
        }
    }

    It 'should install the WSL git-status helper as a user-scoped portable command' {
        $starship = @($script:packages | Where-Object PackageIdentifier -EQ 'Starship.Starship')
        $starship.Count | Should -Be 1
        @($starship[0].installArgs) | Should -Be @('--scope', 'user', '--installer-type', 'zip')
        $starship[0].portableLink.linkName | Should -Be 'starship.exe'
        $starship[0].portableLink.targetPattern | Should -Be 'starship.exe'
        @($starship[0].pathEntries) | Should -Be @('%LOCALAPPDATA%\Microsoft\WinGet\Links')
        $starship[0].persistPathEntries | Should -BeTrue
        @($script:packages | Where-Object persistPathEntries).Count | Should -Be 3
        $starship[0].verifyCommand.type | Should -Be 'portableLinkCommand'
        $starship[0].verifyCommand.command | Should -Be 'starship.exe'
        @($starship[0].verifyCommand.args) | Should -Be @('--version')
        $starship[0].PSObject.Properties.Name | Should -Not -Contain 'ciSkipInstall'
        $retired = Get-Content -LiteralPath (Join-Path $script:repoRoot 'windows/winget/retired-packages.json') -Raw | ConvertFrom-Json
        @($retired.packages | Where-Object id -EQ 'Starship.Starship').Count | Should -Be 0
    }

    It 'should retain the complete MinGit tree and verify its declared cmd directory' {
        $git = @($script:packages | Where-Object PackageIdentifier -EQ 'Git.MinGit')
        $git.Count | Should -Be 1
        @($git[0].installArgs) | Should -Be @('--scope', 'user', '--installer-type', 'zip')
        @($git[0].pathEntries) | Should -Be @('%LOCALAPPDATA%\Microsoft\WinGet\Packages\Git.MinGit_Microsoft.Winget.Source_8wekyb3d8bbwe\cmd')
        $git[0].persistPathEntries | Should -BeTrue
        $git[0].PSObject.Properties.Name | Should -Not -Contain 'portableLink'
        $git[0].verifyCommand.type | Should -Be 'pathEntriesCommand'
        $git[0].verifyCommand.command | Should -Be 'git'
        @($git[0].verifyCommand.args) | Should -Be @('--version')
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
            Should -Be '9PCFS5B6T72H|9PLM9XGG6VKS|StablyAI.Orca'
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
        @{ Id = 'Microsoft.WindowsTerminal'; Command = 'Microsoft.WindowsTerminal'; Target = 'Microsoft.WindowsTerminal_8wekyb3d8bbwe!App' }
        @{ Id = '9PLM9XGG6VKS'; Command = 'OpenAI.Codex'; Target = 'OpenAI.Codex_2p2nqsd0c76g0!App' }
    ) {
        $package = $script:packages | Where-Object PackageIdentifier -EQ $Id
        $package.verifyCommand.type | Should -Be 'appxLaunchTarget'
        $package.verifyCommand.command | Should -Be $Command
        @($package.verifyCommand.args) | Should -Be @($Target)
    }

    It 'should include Paint from Microsoft Store and verify package registration without opening the GUI' {
        $store = @($script:winget.Sources | Where-Object { $_.SourceDetails.Name -eq 'msstore' })
        $paint = @($store.Packages | Where-Object PackageIdentifier -EQ '9PCFS5B6T72H')
        $paint.Count | Should -Be 1
        $paint[0].verifyCommand.type | Should -Be 'appxPackage'
        $paint[0].verifyCommand.command | Should -Be 'Microsoft.Paint'
        $paint[0].verifyCommand.args | Should -BeNullOrEmpty
        $paint[0].ciSkipInstall | Should -BeTrue
    }

    It 'should install pinned Dia from its official AppX source and verify its launch identity' {
        $source = @($script:winget.Sources | Where-Object { $_.SourceDetails.Name -eq 'direct' })
        $source.Count | Should -Be 1
        $source[0].SourceDetails.Identifier | Should -Be 'Dotfiles.DirectInstallers'
        $source[0].SourceDetails.Type | Should -Be 'Dotfiles.DirectInstaller'
        $source[0].SourceDetails.Argument | Should -Be 'https://releases.diabrowser.com'
        $dia = @($source[0].Packages | Where-Object PackageIdentifier -EQ 'TheBrowserCompany.Dia')
        $dia.Count | Should -Be 1
        $dia[0].verifyCommand.type | Should -Be 'appxLaunchTarget'
        $dia[0].verifyCommand.command | Should -Be 'TheBrowserCompany.Dia'
        @($dia[0].verifyCommand.args) | Should -Be @('TheBrowserCompany.Dia_ttt1ap7aakyb4!Dia')
        $dia[0].PSObject.Properties.Name | Should -Not -Contain 'ciSkipInstall'
        $dia[0].PSObject.Properties.Name | Should -Not -Contain 'skipInstall'
        $installer = $dia[0].directInstaller
        $installer.type | Should -Be 'appx'
        $installer.name | Should -Be 'TheBrowserCompany.Dia'
        $installer.packageFamilyName | Should -Be 'TheBrowserCompany.Dia_ttt1ap7aakyb4'
        $installer.version | Should -Match '^\d+\.\d+\.\d+\.\d+$'
        $installer.architecture | Should -Be 'x64'
        $installer.executable | Should -Be 'Dia.exe'
        $installer.publisher | Should -Be 'E=hello@thebrowser.company, CN=THE BROWSER COMPANY OF NEW YORK INC., O=THE BROWSER COMPANY OF NEW YORK INC., STREET=295 LAFAYETTE STREET, L=New York, S=New York, C=US, OID.1.3.6.1.4.1.311.60.2.1.2=Delaware, OID.1.3.6.1.4.1.311.60.2.1.3=US, SERIALNUMBER=7571542, OID.2.5.4.15=Private Organization'
        $officialOrigin = $source[0].SourceDetails.Argument.TrimEnd('/')
        $applicationName = [IO.Path]::GetFileNameWithoutExtension($installer.executable)
        $installer.url | Should -Be "$officialOrigin/windows/release/$($installer.version)/$applicationName.$($installer.architecture).msix"
        $installer.sha256 | Should -Match '^[0-9a-fA-F]{64}$'
        @($installer.dependencies).Count | Should -Be 1
        $installer.dependencies[0].name | Should -Be 'Microsoft.VCLibs.140.00.UWPDesktop'
        $installer.dependencies[0].packageFamilyName | Should -Be 'Microsoft.VCLibs.140.00.UWPDesktop_8wekyb3d8bbwe'
        $installer.dependencies[0].publisher | Should -Be 'CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US'
        $installer.dependencies[0].version | Should -Match '^\d+\.\d+\.\d+\.\d+$'
        $installer.dependencies[0].architecture | Should -Be 'x64'
        $dependency = $installer.dependencies[0]
        $dependencyVersion = [version]$dependency.version
        $runtimeSeries = '{0}.{1:D2}' -f $dependencyVersion.Major, $dependencyVersion.Minor
        $dependency.url | Should -Be "$officialOrigin/windows/dependencies/$($dependency.architecture)/Microsoft.VCLibs.$($dependency.architecture).$runtimeSeries.Desktop.$($dependency.version).appx"
        $dependency.sha256 | Should -Match '^[0-9a-fA-F]{64}$'
    }

    It 'should verify <Id> using an installed-product identity' -ForEach @(
        @{ Id = 'AgileBits.1Password'; Command = 'AgileBits.1Password' }
        @{ Id = 'Discord.Discord'; Command = 'Discord' }
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

    It 'should update flake inputs by default before scripted NixOS rebuild entry points' {
        $taskfile = Get-Content -LiteralPath (Join-Path $script:repoRoot "taskfiles/nix/taskfile.yml") -Raw
        $postInstallScript = Get-Content -LiteralPath (Join-Path $script:repoRoot "scripts/powershell/lib/Invoke-NixosWslSetup.ps1") -Raw
        $commonInstallScript = Get-Content -LiteralPath (Join-Path $script:repoRoot "scripts/sh/install-common.sh") -Raw

        $taskfile | Should -Match 'nix flake update && \{\{end\}\}sudo nixos-rebuild switch --flake \. --impure'
        $commonInstallScript | Should -Match 'nix flake update --flake "\$flake_ref"'
        $postInstallScript | Should -Match 'flake update --flake'
        $commonInstallScript | Should -Not -Match 'dotfiles_trust_git_directory|git config --global'
        $postInstallScript | Should -Not -Match 'git config --global'
    }
}
