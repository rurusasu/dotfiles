#Requires -Module Pester

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    $script:wingetJsonPath = Join-Path $script:repoRoot "windows/winget/packages.json"
    $script:npmJsonPath = Join-Path $script:repoRoot "windows/npm/packages.json"
    $script:pnpmJsonPath = Join-Path $script:repoRoot "windows/pnpm/packages.json"
}

Describe 'Package catalog consistency' {

    Context 'Latest package policy' {
        It 'should not pin winget package versions in generated packages.json' {
            $json = Get-Content -LiteralPath $script:wingetJsonPath -Raw | ConvertFrom-Json
            $versionedPackages = @(
                $json.Sources |
                    ForEach-Object { $_.Packages } |
                    Where-Object { $_.PSObject.Properties.Name -contains 'Version' }
            )

            $versionedPackages.Count | Should -Be 0
        }

        It 'should generate the stable WezTerm package without pinning a version or bypassing hash validation' {
            $json = Get-Content -LiteralPath $script:wingetJsonPath -Raw | ConvertFrom-Json
            $wingetSource = @($json.Sources | Where-Object { $_.SourceDetails.Name -eq 'winget' }) | Select-Object -First 1
            $package = @($wingetSource.Packages | Where-Object { $_.PackageIdentifier -eq 'wez.wezterm' }) | Select-Object -First 1

            $package | Should -Not -BeNullOrEmpty
            @($package.installArgs) | Should -Not -Contain '--ignore-security-hash'
            $package.PSObject.Properties.Name | Should -Not -Contain 'Version'
        }

        It 'should generate terminal packages without normal-run or CI skip metadata' {
            $json = Get-Content -LiteralPath $script:wingetJsonPath -Raw | ConvertFrom-Json
            $wingetSource = @($json.Sources | Where-Object { $_.SourceDetails.Name -eq 'winget' }) | Select-Object -First 1
            $wezterm = @($wingetSource.Packages | Where-Object { $_.PackageIdentifier -eq 'wez.wezterm' }) | Select-Object -First 1

            $wezterm | Should -Not -BeNullOrEmpty
            $wezterm.PSObject.Properties.Name | Should -Not -Contain 'skipInstall'
            $wezterm.PSObject.Properties.Name | Should -Not -Contain 'skipReason'
            $wezterm.PSObject.Properties.Name | Should -Not -Contain 'ciSkipInstall'
        }


        It 'should keep Raycast and Dia out of the generated Windows manifest' {
            $json = Get-Content -LiteralPath $script:wingetJsonPath -Raw | ConvertFrom-Json
            $wingetSource = @($json.Sources | Where-Object { $_.SourceDetails.Name -eq 'winget' }) | Select-Object -First 1
            @($wingetSource.Packages | Where-Object { $_.PackageIdentifier -eq 'Raycast.Raycast' }).Count | Should -Be 0
            @($wingetSource.Packages | Where-Object { $_.PackageIdentifier -eq 'TheBrowserCompany.Dia' }).Count | Should -Be 0
        }

        It 'should update flake inputs before setup and rebuild' {
            $taskfile = Get-Content -LiteralPath (Join-Path $script:repoRoot "taskfiles/nix/taskfile.yml") -Raw
            $postInstallScript = Get-Content -LiteralPath (Join-Path $script:repoRoot "scripts/powershell/lib/Invoke-NixosWslSetup.ps1") -Raw
            $commonInstallScript = Get-Content -LiteralPath (Join-Path $script:repoRoot "scripts/sh/install-common.sh") -Raw

            $taskfile | Should -Match 'nix flake update && sudo nixos-rebuild switch --flake \. --impure'
            $commonInstallScript | Should -Match 'nix flake update --flake "\$flake_ref"'
            $postInstallScript | Should -Match 'flake update --flake'
            $commonInstallScript | Should -Not -Match 'dotfiles_trust_git_directory|git config --global'
            $postInstallScript | Should -Not -Match 'git config --global'
        }

    }

    Context 'Windows-only WSL package' {
        It 'should generate Microsoft.WSL into windows winget packages.json under the winget source' {
            $json = Get-Content -LiteralPath $script:wingetJsonPath -Raw | ConvertFrom-Json
            $wingetSource = @($json.Sources | Where-Object { $_.SourceDetails.Name -eq 'winget' }) | Select-Object -First 1
            $package = @($wingetSource.Packages | Where-Object { $_.PackageIdentifier -eq 'Microsoft.WSL' }) | Select-Object -First 1

            $package | Should -Not -BeNullOrEmpty
        }

        It 'should verify Microsoft.WSL by running wsl --version with timeout and repair then reinstall recovery' {
            $json = Get-Content -LiteralPath $script:wingetJsonPath -Raw | ConvertFrom-Json
            $wingetSource = @($json.Sources | Where-Object { $_.SourceDetails.Name -eq 'winget' }) | Select-Object -First 1
            $package = @($wingetSource.Packages | Where-Object { $_.PackageIdentifier -eq 'Microsoft.WSL' }) | Select-Object -First 1

            $package.verifyCommand.command | Should -Be 'wsl'
            @($package.verifyCommand.args) | Should -Contain '--version'
            $package.verifyCommand.timeoutSeconds | Should -Be 120
            $package.verifyCommand.recoveryStrategy | Should -Be 'wingetRepairThenReinstall'
        }
    }

    Context 'slow CLI verifier timeouts' {
        It 'should preserve package-scoped GitHub CLI, Go and WSL verification windows' {
            $json = Get-Content -LiteralPath $script:wingetJsonPath -Raw | ConvertFrom-Json
            $wingetSource = @($json.Sources | Where-Object { $_.SourceDetails.Name -eq 'winget' }) | Select-Object -First 1
            $gh = @($wingetSource.Packages | Where-Object PackageIdentifier -EQ 'GitHub.cli') | Select-Object -First 1
            $go = @($wingetSource.Packages | Where-Object PackageIdentifier -EQ 'GoLang.Go') | Select-Object -First 1

            $gh.verifyCommand.timeoutSeconds | Should -Be 60
            $go.verifyCommand.timeoutSeconds | Should -Be 3600
            (@($wingetSource.Packages | Where-Object { $_.verifyCommand.timeoutSeconds } | ForEach-Object { "$($_.PackageIdentifier):$($_.verifyCommand.timeoutSeconds)" } | Sort-Object) -join ',') |
                Should -Be 'GitHub.cli:60,GoLang.Go:3600,Microsoft.WSL:120' -Because 'verification timeouts must remain package-scoped'
        }
    }

    Context 'Google Cloud SDK package' {
        It 'should generate Google.CloudSDK gcloud PATH and verification metadata' {
            $json = Get-Content -LiteralPath $script:wingetJsonPath -Raw | ConvertFrom-Json
            $wingetSource = @($json.Sources | Where-Object { $_.SourceDetails.Name -eq 'winget' }) | Select-Object -First 1
            $package = @($wingetSource.Packages | Where-Object { $_.PackageIdentifier -eq 'Google.CloudSDK' }) | Select-Object -First 1

            $package | Should -Not -BeNullOrEmpty
            @($package.pathEntries) | Should -Contain '%ProgramFiles%\Google\Cloud SDK\google-cloud-sdk\bin'
            @($package.pathEntries) | Should -Contain '%ProgramFiles(x86)%\Google\Cloud SDK\google-cloud-sdk\bin'
            @($package.pathEntries) | Should -Contain '%LOCALAPPDATA%\Google\Cloud SDK\google-cloud-sdk\bin'
            $package.verifyCommand.command | Should -Be 'gcloud'
            @($package.verifyCommand.args) | Should -Contain 'version'
        }

        It 'should assign the shared install timeout to every winget source package' {
            $json = Get-Content -LiteralPath $script:wingetJsonPath -Raw | ConvertFrom-Json
            $packages = @($json.Sources | ForEach-Object { @($_.Packages) })

            $packages.Count | Should -BeGreaterThan 0
            @($packages | Where-Object { $_.installTimeoutSeconds -ne 3600 }).Count | Should -Be 0
        }
    }

    Context 'WinGet package PATH' {
        It 'should expose the Task executable directory to package verification' {
            $winget = Get-Content -LiteralPath $script:wingetJsonPath -Raw | ConvertFrom-Json
            $task = @($winget.Sources | ForEach-Object { $_.Packages } | Where-Object PackageIdentifier -EQ 'Task.Task') | Select-Object -First 1

            @($task.pathEntries) | Should -Contain '%LOCALAPPDATA%\Microsoft\WinGet\Packages\Task.Task*'
        }

        It 'should expose each installed CLI package root required by its verifier' {
            $winget = Get-Content -LiteralPath $script:wingetJsonPath -Raw | ConvertFrom-Json
            $wingetSource = @($winget.Sources | Where-Object { $_.SourceDetails.Name -eq 'winget' }) | Select-Object -First 1
            $expectedRoots = @{
                'Task.Task'                   = '%LOCALAPPDATA%\Microsoft\WinGet\Packages\Task.Task*'
                'hadolint.hadolint'           = '%LOCALAPPDATA%\Microsoft\WinGet\Packages\hadolint.hadolint*'
                'tree-sitter.tree-sitter-cli' = '%LOCALAPPDATA%\Microsoft\WinGet\Packages\tree-sitter.tree-sitter-cli*'
                'astral-sh.uv'                = '%LOCALAPPDATA%\Microsoft\WinGet\Packages\astral-sh.uv*'
            }

            foreach ($id in $expectedRoots.Keys) {
                $package = @($wingetSource.Packages | Where-Object PackageIdentifier -EQ $id) | Select-Object -First 1
                $package | Should -Not -BeNullOrEmpty -Because "$id must remain in the generated package catalog"
                @($package.pathEntries) | Should -Contain $expectedRoots[$id] -Because "$id's verifier runs its executable from the package root"
            }
        }


        It 'should generate the Node.js installation directory into winget packages.json' {
            $json = Get-Content -LiteralPath $script:wingetJsonPath -Raw | ConvertFrom-Json
            $wingetSource = @($json.Sources | Where-Object { $_.SourceDetails.Name -eq 'winget' }) | Select-Object -First 1
            $package = @($wingetSource.Packages | Where-Object { $_.PackageIdentifier -eq 'OpenJS.NodeJS.LTS' }) | Select-Object -First 1

            $package | Should -Not -BeNullOrEmpty
            @($package.pathEntries) | Should -Contain '%ProgramFiles%\nodejs'
        }
    }

    Context '1Password CLI package' {
        It 'should generate op package path metadata into winget packages.json' {
            $json = Get-Content -LiteralPath $script:wingetJsonPath -Raw | ConvertFrom-Json
            $wingetSource = @($json.Sources | Where-Object { $_.SourceDetails.Name -eq 'winget' }) | Select-Object -First 1
            $package = @($wingetSource.Packages | Where-Object { $_.PackageIdentifier -eq 'AgileBits.1Password.CLI' }) | Select-Object -First 1

            $package | Should -Not -BeNullOrEmpty
            @($package.pathEntries) | Should -Contain '%LOCALAPPDATA%\Microsoft\WinGet\Packages\AgileBits.1Password.CLI*'
            @($package.installArgs) | Should -Contain '--scope'
            @($package.installArgs) | Should -Contain 'user'
            $package.PSObject.Properties.Name | Should -Not -Contain 'portableLink'
            $package.verifyCommand.command | Should -Be 'op'
            @($package.verifyCommand.args) | Should -Contain '--version'
        }
    }

    Context 'Codex CLI package' {
        It 'should omit the separately installed Codex npm package' {
            $json = Get-Content -LiteralPath $script:npmJsonPath -Raw | ConvertFrom-Json
            @($json.globalPackages | Where-Object { $_.name -eq '@openai/codex' }).Count | Should -Be 0
        }

    }


    Context 'Codex Desktop Microsoft Store package' {
        It 'should generate Codex Desktop under the msstore source with launch target verification' {
            $json = Get-Content -LiteralPath $script:wingetJsonPath -Raw | ConvertFrom-Json
            $msstoreSource = @($json.Sources | Where-Object { $_.SourceDetails.Name -eq 'msstore' }) | Select-Object -First 1
            $package = @($msstoreSource.Packages | Where-Object { $_.PackageIdentifier -eq '9PLM9XGG6VKS' }) | Select-Object -First 1

            $package | Should -Not -BeNullOrEmpty
            $package.ciSkipInstall | Should -BeTrue
            $package.verifyCommand.type | Should -Be 'appxLaunchTarget'
            $package.verifyCommand.command | Should -Be 'OpenAI.Codex'
            @($package.verifyCommand.args) | Should -Contain 'OpenAI.Codex_2p2nqsd0c76g0!App'
        }
    }

    Context 'Devcontainer CLI package' {
        It 'should generate @devcontainers/cli into the Windows npm package catalog with verification' {
            $json = Get-Content -LiteralPath $script:npmJsonPath -Raw | ConvertFrom-Json
            $package = @($json.globalPackages | Where-Object { $_.name -eq '@devcontainers/cli' }) | Select-Object -First 1

            $package | Should -Not -BeNullOrEmpty
            $package.verifyCommand.command | Should -Be 'devcontainer'
            @($package.verifyCommand.args) | Should -Contain '--version'
        }

    }

    Context 'Orca and uv installation policy' {
        It 'should generate Orca and uv with verification metadata' {
            $json = Get-Content -LiteralPath $script:wingetJsonPath -Raw | ConvertFrom-Json
            $wingetSource = @($json.Sources | Where-Object { $_.SourceDetails.Name -eq 'winget' }) | Select-Object -First 1
            $orca = @($wingetSource.Packages | Where-Object { $_.PackageIdentifier -eq 'StablyAI.Orca' }) | Select-Object -First 1
            $uv = @($wingetSource.Packages | Where-Object { $_.PackageIdentifier -eq 'astral-sh.uv' }) | Select-Object -First 1

            $orca | Should -Not -BeNullOrEmpty
            $orca.ciSkipInstall | Should -BeTrue
            $uv | Should -Not -BeNullOrEmpty
            $uv.verifyCommand.command | Should -Be 'uv'
            @($uv.verifyCommand.args) | Should -Contain '--version'
        }
    }

    Context 'PowerToys Windows installation verification' {
        It 'should match the user installer ARP display name and require a versioned executable' {
            $json = Get-Content -LiteralPath $script:wingetJsonPath -Raw | ConvertFrom-Json
            $wingetSource = @($json.Sources | Where-Object { $_.SourceDetails.Name -eq 'winget' }) | Select-Object -First 1
            $package = @($wingetSource.Packages | Where-Object PackageIdentifier -EQ 'Microsoft.PowerToys') | Select-Object -First 1
            $entry = $package.verifyCommand.uninstallEntry

            $package | Should -Not -BeNullOrEmpty
            $entry.displayNamePattern | Should -Not -BeNullOrEmpty
            $entry.displayNamePattern | Should -Match 'PowerToys'
            'PowerToys' | Should -Match $entry.displayNamePattern
            'PowerToys (Preview)' | Should -Match $entry.displayNamePattern
            'Microsoft PowerToys Preview' | Should -Not -Match $entry.displayNamePattern
            $entry.publisher | Should -Be 'Microsoft Corporation'
            @($entry.executablePaths) | Should -Contain '%LOCALAPPDATA%\PowerToys\PowerToys.exe'
        }
    }

    Context 'Windows native Rust browser automation tools' {
        It 'should generate agent-browser into the Windows npm package catalog with verification' {
            $json = Get-Content -LiteralPath $script:npmJsonPath -Raw | ConvertFrom-Json
            $package = @($json.globalPackages | Where-Object { $_.name -eq 'agent-browser@0.38.1' }) | Select-Object -First 1

            $package | Should -Not -BeNullOrEmpty
            $package.verifyCommand.command | Should -Be 'agent-browser'
            @($package.verifyCommand.args) | Should -Contain '--version'
        }

        It 'should generate Visual Studio Build Tools with C++ workload install metadata' {
            $json = Get-Content -LiteralPath $script:wingetJsonPath -Raw | ConvertFrom-Json
            $wingetSource = @($json.Sources | Where-Object { $_.SourceDetails.Name -eq 'winget' }) | Select-Object -First 1
            $package = @($wingetSource.Packages | Where-Object { $_.PackageIdentifier -eq 'Microsoft.VisualStudio.2022.BuildTools' }) | Select-Object -First 1

            $package | Should -Not -BeNullOrEmpty
            @($package.installArgs) | Should -Contain '--override'
            @($package.installArgs) | Should -Contain '--add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --passive --wait --norestart'
        }
    }

    Context 'Cross-platform package providers' {



        It 'should install dsh with npm and leave pnpm packages empty' {
            $pnpm = Get-Content -LiteralPath $script:pnpmJsonPath -Raw | ConvertFrom-Json
            @($pnpm.globalPackages).Count | Should -Be 0
            $npm = Get-Content -LiteralPath $script:npmJsonPath -Raw | ConvertFrom-Json
            $dsh = @($npm.globalPackages | Where-Object { $_.name -eq '@deepseek-ai/dsh' }) | Select-Object -First 1

            $dsh | Should -Not -BeNullOrEmpty
            @($dsh.installArgs) | Should -Not -Contain '--allow-build=node-pty'
        }

        It 'should omit Bun from the Windows manifest' {
            $winget = Get-Content -LiteralPath $script:wingetJsonPath -Raw | ConvertFrom-Json
            @($winget.Sources.Packages | Where-Object PackageIdentifier -EQ 'Oven-sh.Bun').Count | Should -Be 0
        }

        It 'should provide direct fallbacks for portable packages affected by WinGet registration hangs' {
            $winget = Get-Content -LiteralPath $script:wingetJsonPath -Raw | ConvertFrom-Json
            $wingetSource = @($winget.Sources | Where-Object { $_.SourceDetails.Name -eq 'winget' }) | Select-Object -First 1
            $fallbackIds = @(
                'twpayne.chezmoi'
                'direnv.direnv'
                'dprint.dprint'
                'sharkdp.fd'
                'eza-community.eza'
            )

            foreach ($id in $fallbackIds) {
                $package = @($wingetSource.Packages | Where-Object PackageIdentifier -EQ $id) | Select-Object -First 1
                $package | Should -Not -BeNullOrEmpty -Because "$id must remain in the generated catalog"
                $package.directInstaller.type | Should -BeIn @('archive', 'file')
                $package.directInstaller.url | Should -Match '^https://'
                $package.directInstaller.sha256 | Should -Match '^[0-9a-f]{64}$'
                @($package.pathEntries).Count | Should -BeGreaterThan 0
            }
        }

        It 'should generate AutoHotkey for the Windows terminal keybinding adapter' {
            $winget = Get-Content -LiteralPath $script:wingetJsonPath -Raw | ConvertFrom-Json
            $wingetSource = @($winget.Sources | Where-Object { $_.SourceDetails.Name -eq 'winget' }) | Select-Object -First 1
            $package = @($wingetSource.Packages | Where-Object PackageIdentifier -EQ 'AutoHotkey.AutoHotkey')
            $package.Count | Should -Be 1
            @($package[0].installArgs) | Should -Contain '--scope'
            @($package[0].installArgs) | Should -Contain 'machine'
            $package[0].requiresAdmin | Should -BeTrue
        }


        It 'should preserve the active ChatGPT package and retired package cleanup metadata' {
            $winget = Get-Content -LiteralPath $script:wingetJsonPath -Raw | ConvertFrom-Json
            $storeSource = @($winget.Sources | Where-Object { $_.SourceDetails.Name -eq 'msstore' }) | Select-Object -First 1

            @($storeSource.Packages | Where-Object PackageIdentifier -EQ '9PLM9XGG6VKS').Count | Should -Be 1

            $retiredPath = Join-Path (Split-Path -Parent $script:wingetJsonPath) 'retired-packages.json'
            $retired = Get-Content -LiteralPath $retiredPath -Raw | ConvertFrom-Json
            @($retired.packages | Where-Object { $_.id -eq '9NT1R1C2HH7J' -and $_.source -eq 'msstore' -and $_.name -eq 'ChatGPT Classic' }).Count | Should -Be 1
            @($retired.packages | Where-Object { $_.id -eq 'OpenAI.Codex' -and $_.source -eq 'winget' -and $_.name -eq 'Codex CLI' }).Count | Should -Be 1
            @($retired.packages | Where-Object { $_.id -eq '9PLM9XGG6VKS' }).Count | Should -Be 0
        }

        It 'should not install Docker Desktop on Windows' {
            $wingetWithoutDocker = Get-Content -LiteralPath $script:wingetJsonPath -Raw | ConvertFrom-Json
            @($wingetWithoutDocker.Sources | ForEach-Object { $_.Packages } | Where-Object PackageIdentifier -EQ 'Docker.DockerDesktop').Count | Should -Be 0
        }

        It 'should require a concrete verifier for every entry in nonempty Windows manifests' {
            $winget = Get-Content -LiteralPath $script:wingetJsonPath -Raw | ConvertFrom-Json
            $wingetPackages = @($winget.Sources | ForEach-Object { $_.Packages })
            $winGetOnlyPackages = @($winget.Sources | Where-Object { $_.SourceDetails.Name -eq 'winget' } | ForEach-Object { $_.Packages })
            $storePackages = @($winget.Sources | Where-Object { $_.SourceDetails.Name -eq 'msstore' } | ForEach-Object { $_.Packages })
            $npm = Get-Content -LiteralPath $script:npmJsonPath -Raw | ConvertFrom-Json
            $pnpm = Get-Content -LiteralPath $script:pnpmJsonPath -Raw | ConvertFrom-Json
            $packageCount = $wingetPackages.Count + @($npm.globalPackages).Count + @($pnpm.globalPackages).Count
            $specialVerifiers = @{
                'AgileBits.1Password'                    = @{ type = 'windowsInstalledProduct'; command = 'AgileBits.1Password' }
                'AutoHotkey.AutoHotkey'                  = @{ type = 'windowsInstalledProduct'; command = 'AutoHotkey' }
                'Discord.Discord'                        = @{ type = 'windowsInstalledProduct'; command = 'Discord' }
                'Google.Chrome'                          = @{ type = 'windowsInstalledProduct'; command = 'Google Chrome' }
                'Obsidian.Obsidian'                      = @{ type = 'windowsInstalledProduct'; command = 'Obsidian' }
                'StablyAI.Orca'                          = @{ type = 'windowsInstalledProduct'; command = 'OrcaSlicer' }
                'Microsoft.PowerToys'                    = @{ type = 'windowsInstalledProduct'; command = 'Microsoft PowerToys' }
                'Microsoft.VCRedist.2015+.x64'           = @{ type = 'windowsInstalledProduct'; command = 'Microsoft Visual C++ 2015-2022 Redistributable (x64)' }
                'Microsoft.VisualStudio.2022.BuildTools' = @{ type = 'visualStudioInstanceVersion'; command = 'Microsoft.VisualStudio.Product.BuildTools' }
            }
            $supportedTypes = @('command', 'commandExists', 'appxPackage', 'appxLaunchTarget', 'portableLinkCommand', 'windowsInstalledProduct', 'visualStudioInstanceVersion')

            $packageCount | Should -BeGreaterThan 0
            @($winget.Sources | Where-Object { $_.SourceDetails.Name -eq 'winget' } | ForEach-Object { $_.Packages }).Count | Should -BeGreaterThan 0
            @($winget.Sources | Where-Object { $_.SourceDetails.Name -eq 'msstore' } | ForEach-Object { $_.Packages }).Count | Should -BeGreaterThan 0
            @($wingetPackages | ForEach-Object { $_.PackageIdentifier }).Count | Should -Be @($wingetPackages | ForEach-Object { $_.PackageIdentifier } | Select-Object -Unique).Count
            @($npm.globalPackages | Where-Object { $null -eq $_.verifyCommand }).Count | Should -Be 0
            @($pnpm.globalPackages | Where-Object { $null -eq $_.verifyCommand }).Count | Should -Be 0

            foreach ($package in @($npm.globalPackages) + @($pnpm.globalPackages)) {
                [string]::IsNullOrWhiteSpace([string]$package.verifyCommand.command) | Should -BeFalse -Because "$($package.name) must identify its verification executable"
                $verifyType = if ([string]::IsNullOrWhiteSpace([string]$package.verifyCommand.type)) { 'command' } else { [string]$package.verifyCommand.type }
                if ($verifyType -eq 'commandExists') {
                    @($package.verifyCommand.args | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count |
                        Should -Be 0 -Because "$($package.name) command-existence verifier must not execute the command"
                }
                else {
                    @($package.verifyCommand.args).Count | Should -BeGreaterThan 0 -Because "$($package.name) must execute a verification command"
                    @($package.verifyCommand.args | Where-Object { [string]::IsNullOrWhiteSpace([string]$_) }).Count | Should -Be 0 -Because "$($package.name) verifier arguments must be concrete"
                }
            }

            (@($winGetOnlyPackages | Where-Object ciSkipInstall | ForEach-Object PackageIdentifier | Sort-Object) -join ',') |
                Should -Be 'Google.CloudSDK,StablyAI.Orca' -Because 'CI runtime exclusions must remain explicit and reviewed'
            @($storePackages | Where-Object ciSkipInstall | ForEach-Object PackageIdentifier) | Should -Be @('9PLM9XGG6VKS')
            (@($winGetOnlyPackages | Where-Object requiresAdmin | ForEach-Object PackageIdentifier | Sort-Object) -join ',') |
                Should -Be 'AutoHotkey.AutoHotkey,glzr-io.glazewm,Microsoft.VisualStudio.2022.BuildTools' -Because 'admin phase exclusions must remain explicit and reviewed'

            foreach ($package in $wingetPackages) {
                $id = [string]$package.PackageIdentifier
                $package.verifyCommand | Should -Not -BeNullOrEmpty -Because "$id must have an executable or installed-artifact verifier"
                $type = if ([string]::IsNullOrWhiteSpace([string]$package.verifyCommand.type)) { 'command' } else { [string]$package.verifyCommand.type }
                $supportedTypes | Should -Contain $type -Because "$id must use a verifier implemented by Handler.Winget"
                [string]::IsNullOrWhiteSpace([string]$package.verifyCommand.command) | Should -BeFalse -Because "$id must identify what the verifier checks"
                if ($specialVerifiers.ContainsKey($id)) {
                    $type | Should -Be $specialVerifiers[$id].type -Because "$id must use its package-specific non-launching verification strategy"
                    [string]$package.verifyCommand.command | Should -Be $specialVerifiers[$id].command
                    if ($type -eq 'windowsInstalledProduct') {
                        $hasAppxIdentity = $null -ne $package.verifyCommand.appxPackage
                        $hasUninstallIdentity = $null -ne $package.verifyCommand.uninstallEntry
                        ($hasAppxIdentity -or $hasUninstallIdentity) | Should -BeTrue -Because "$id must identify the installed product"
                        if ($hasAppxIdentity) {
                            $package.verifyCommand.appxPackage.name | Should -Not -BeNullOrEmpty
                            $package.verifyCommand.appxPackage.packageFamilyName | Should -Not -BeNullOrEmpty
                            $package.verifyCommand.appxPackage.executable | Should -Not -BeNullOrEmpty
                        }
                        if ($hasUninstallIdentity) {
                            $identity = $package.verifyCommand.uninstallEntry
                            ($identity.productCodes.Count -gt 0 -or $identity.displayName -or $identity.displayNamePattern) |
                                Should -BeTrue -Because "$id must identify its uninstall registration"
                            @($identity.executablePaths).Count | Should -BeGreaterThan 0 -Because "$id must validate an installed executable version"
                        }
                    }
                }
            }

            $onePassword = $wingetPackages | Where-Object PackageIdentifier -EQ 'AgileBits.1Password'
            $onePassword.verifyCommand.appxPackage.packageFamilyName | Should -Be 'Agilebits.1Password_amwd9z03whsfe'
            $onePassword.verifyCommand.appxPackage.executable | Should -Be '1Password.exe'
            @($onePassword.verifyCommand.uninstallEntry.executablePaths).Count | Should -BeGreaterThan 0
            $vsBuildTools = $wingetPackages | Where-Object PackageIdentifier -EQ 'Microsoft.VisualStudio.2022.BuildTools'
            $vsBuildTools.verifyCommand.requiredComponent | Should -Be 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64'
            $vsBuildTools.verifyCommand.minimumVersion | Should -Be '17.0'
            $vsBuildTools.verifyCommand.compilerRelativePath | Should -Match 'cl\.exe$'
            $vcRuntime = $wingetPackages | Where-Object PackageIdentifier -EQ 'Microsoft.VCRedist.2015+.x64'
            $vcRuntime.verifyCommand.uninstallEntry.displayNamePattern | Should -Match 'v14 Redistributable'
        }

        It 'should verify Arc and Windows Terminal AppX identity, install path, and application ID without launching them' {
            $winget = Get-Content -LiteralPath $script:wingetJsonPath -Raw | ConvertFrom-Json
            $wingetSource = @($winget.Sources | Where-Object { $_.SourceDetails.Name -eq 'winget' }) | Select-Object -First 1
            $expectedAppxTargets = @{
                'TheBrowserCompany.Arc'     = @{
                    PackageName       = 'TheBrowserCompany.Arc'
                    PackageFamilyName = 'TheBrowserCompany.Arc_ttt1ap7aakyb4'
                    AppUserModelId    = 'TheBrowserCompany.Arc_ttt1ap7aakyb4!Arc'
                }
                'Microsoft.WindowsTerminal' = @{
                    PackageName       = 'Microsoft.WindowsTerminal'
                    PackageFamilyName = 'Microsoft.WindowsTerminal_8wekyb3d8bbwe'
                    AppUserModelId    = 'Microsoft.WindowsTerminal_8wekyb3d8bbwe!App'
                }
            }

            foreach ($id in $expectedAppxTargets.Keys) {
                $package = @($wingetSource.Packages | Where-Object PackageIdentifier -EQ $id)
                $package.Count | Should -Be 1
                $package[0].verifyCommand.type | Should -Be 'appxLaunchTarget'
                $package[0].verifyCommand.command | Should -Be $expectedAppxTargets[$id].PackageName
                @($package[0].verifyCommand.args) | Should -Be @($expectedAppxTargets[$id].AppUserModelId)
                $expectedAppxTargets[$id].AppUserModelId.Split('!')[0] | Should -Be $expectedAppxTargets[$id].PackageFamilyName
            }
        }

    }
}
