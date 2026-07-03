#Requires -Module Pester

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    $script:setsPath = Join-Path $script:repoRoot "nix/packages/sets.nix"
    $script:wingetJsonPath = Join-Path $script:repoRoot "windows/winget/packages.json"
    $script:npmJsonPath = Join-Path $script:repoRoot "windows/npm/packages.json"
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

        It 'should not require InstallerHashOverride for WezTerm nightly' {
            $sets = Get-Content -LiteralPath $script:setsPath -Raw

            $sets | Should -Not -Match '(?s)wingetInstallArgs\s*=\s*\{.*?wezterm\s*=\s*\[.*?"--ignore-security-hash"'
        }

        It 'should generate WezTerm nightly without ignore-security-hash install args' {
            $json = Get-Content -LiteralPath $script:wingetJsonPath -Raw | ConvertFrom-Json
            $wingetSource = @($json.Sources | Where-Object { $_.SourceDetails.Name -eq 'winget' }) | Select-Object -First 1
            $package = @($wingetSource.Packages | Where-Object { $_.PackageIdentifier -eq 'wez.wezterm.nightly' }) | Select-Object -First 1

            $package | Should -Not -BeNullOrEmpty
            @($package.installArgs) | Should -Not -Contain '--ignore-security-hash'
        }

        It 'should keep terminal packages installable during normal winget runs' {
            $sets = Get-Content -LiteralPath $script:setsPath -Raw

            $sets | Should -Not -Match '(?ms)^\s*wingetSkipInstall\s*=\s*\{[^}]*^\s*wezterm\s*='
            $sets | Should -Not -Match '(?ms)^\s*wingetSkipInstall\s*=\s*\{[^}]*^\s*warp-terminal\s*='
        }

        It 'should generate terminal packages without normal-run skipInstall metadata' {
            $json = Get-Content -LiteralPath $script:wingetJsonPath -Raw | ConvertFrom-Json
            $wingetSource = @($json.Sources | Where-Object { $_.SourceDetails.Name -eq 'winget' }) | Select-Object -First 1
            $warp = @($wingetSource.Packages | Where-Object { $_.PackageIdentifier -eq 'Warp.Warp' }) | Select-Object -First 1
            $wezterm = @($wingetSource.Packages | Where-Object { $_.PackageIdentifier -eq 'wez.wezterm.nightly' }) | Select-Object -First 1

            $warp | Should -Not -BeNullOrEmpty
            $warp.PSObject.Properties.Name | Should -Not -Contain 'skipInstall'
            $warp.PSObject.Properties.Name | Should -Not -Contain 'skipReason'
            $wezterm | Should -Not -BeNullOrEmpty
            $wezterm.PSObject.Properties.Name | Should -Not -Contain 'skipInstall'
            $wezterm.PSObject.Properties.Name | Should -Not -Contain 'skipReason'
        }

        It 'should keep volatile terminal installers out of CI-only winget verification' {
            $json = Get-Content -LiteralPath $script:wingetJsonPath -Raw | ConvertFrom-Json
            $wingetSource = @($json.Sources | Where-Object { $_.SourceDetails.Name -eq 'winget' }) | Select-Object -First 1
            $warp = @($wingetSource.Packages | Where-Object { $_.PackageIdentifier -eq 'Warp.Warp' }) | Select-Object -First 1
            $wezterm = @($wingetSource.Packages | Where-Object { $_.PackageIdentifier -eq 'wez.wezterm.nightly' }) | Select-Object -First 1

            $warp.ciSkipInstall | Should -BeTrue
            $wezterm.ciSkipInstall | Should -BeTrue
        }

        It 'should cap Warp direct installer time so install.cmd cannot hang indefinitely' {
            $json = Get-Content -LiteralPath $script:wingetJsonPath -Raw | ConvertFrom-Json
            $wingetSource = @($json.Sources | Where-Object { $_.SourceDetails.Name -eq 'winget' }) | Select-Object -First 1
            $warp = @($wingetSource.Packages | Where-Object { $_.PackageIdentifier -eq 'Warp.Warp' }) | Select-Object -First 1

            $warp.directInstaller.timeoutSeconds | Should -Be 900
        }

        It 'should install Warp through the direct user-scope Inno installer during normal winget runs' {
            $sets = Get-Content -LiteralPath $script:setsPath -Raw
            $json = Get-Content -LiteralPath $script:wingetJsonPath -Raw | ConvertFrom-Json
            $wingetSource = @($json.Sources | Where-Object { $_.SourceDetails.Name -eq 'winget' }) | Select-Object -First 1
            $warp = @($wingetSource.Packages | Where-Object { $_.PackageIdentifier -eq 'Warp.Warp' }) | Select-Object -First 1

            $sets | Should -Match '(?s)wingetDirectInstallers\s*=\s*\{.*?warp-terminal\s*=\s*\{.*?type\s*=\s*"warpInnoLatest"'
            $warp.directInstaller.type | Should -Be 'warpInnoLatest'
            @($warp.directInstaller.installerArgs) | Should -Contain '/CURRENTUSER'
            @($warp.directInstaller.installerArgs) | Should -Contain '/VERYSILENT'
        }

        It 'should update flake inputs in the Nix rebuild aliases before applying the system' {
            $wslUsers = Get-Content -LiteralPath (Join-Path $script:repoRoot "nix/home/wsl/users.nix") -Raw
            $linuxUsers = Get-Content -LiteralPath (Join-Path $script:repoRoot "nix/home/linux/users.nix") -Raw

            $wslUsers | Should -Match 'nrs\s*=\s*"nix flake update --flake ~/.dotfiles && sudo nixos-rebuild switch --flake ~/.dotfiles --impure'
            $linuxUsers | Should -Match 'nrs\s*=\s*"nix flake update --flake ~/.dotfiles && sudo nixos-rebuild switch --flake ~/.dotfiles --impure'
        }

        It 'should update flake inputs before every scripted NixOS rebuild entry point' {
            $taskfile = Get-Content -LiteralPath (Join-Path $script:repoRoot "Taskfile.yml") -Raw
            $updateScript = Get-Content -LiteralPath (Join-Path $script:repoRoot "scripts/sh/update.sh") -Raw
            $postInstallScript = Get-Content -LiteralPath (Join-Path $script:repoRoot "scripts/sh/nixos-wsl-postinstall.sh") -Raw

            $taskfile | Should -Match 'nix flake update && sudo nixos-rebuild switch --flake \. --impure'
            $updateScript | Should -Match 'nix flake update --flake ~/.dotfiles'
            $postInstallScript | Should -Match 'nix flake update --flake "\$TARGET_DIR"'
        }

        It 'should source gwq from a flake input so nix flake update can move it forward' {
            $flake = Get-Content -LiteralPath (Join-Path $script:repoRoot "flake.nix") -Raw
            $sets = Get-Content -LiteralPath $script:setsPath -Raw
            $gwqPackage = Get-Content -LiteralPath (Join-Path $script:repoRoot "nix/packages/gwq/default.nix") -Raw

            $flake | Should -Match 'gwq-src\s*=\s*\{'
            $flake | Should -Match 'url\s*=\s*"github:d-kuro/gwq"'
            $sets | Should -Match 'gwqSrc \? null'
            $sets | Should -Match 'src = gwqSrc'
            $gwqPackage | Should -Match 'version = if src == null then "0\.1\.1" else "unstable"'
        }
    }

    Context 'Windows-only WSL package' {
        It 'should include Microsoft.WSL as a Windows-only winget package in the SSOT' {
            $sets = Get-Content -LiteralPath $script:setsPath -Raw

            $sets | Should -Match '(?s)windowsOnly\s*=\s*\{.*?winget\s*=\s*\[.*?"Microsoft\.WSL".*?\]'
        }

        It 'should define Microsoft.WSL verification as a timed runtime check with repair then reinstall recovery in the SSOT' {
            $sets = Get-Content -LiteralPath $script:setsPath -Raw

            $sets | Should -Match '(?s)"Microsoft\.WSL"\s*=\s*\{.*?command\s*=\s*"wsl".*?args\s*=\s*\[\s*"--version"\s*\].*?timeoutSeconds\s*=\s*30.*?recoveryStrategy\s*=\s*"wingetRepairThenReinstall"'
        }

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
            $package.verifyCommand.timeoutSeconds | Should -Be 30
            $package.verifyCommand.recoveryStrategy | Should -Be 'wingetRepairThenReinstall'
        }
    }

    Context 'Google Cloud SDK package' {
        It 'should define a longer winget install timeout and gcloud PATH entry in the SSOT' {
            $sets = Get-Content -LiteralPath $script:setsPath -Raw

            $sets | Should -Match '(?s)wingetInstallTimeoutSeconds\s*=\s*\{.*?google-cloud-sdk\s*=\s*900'
            $sets | Should -Match '(?s)wingetPathEntries\s*=\s*\{.*?google-cloud-sdk\s*=\s*\[.*?%ProgramFiles%\\\\Google\\\\Cloud SDK\\\\google-cloud-sdk\\\\bin'
            $sets | Should -Match '(?s)wingetPathEntries\s*=\s*\{.*?google-cloud-sdk\s*=\s*\[.*?%ProgramFiles\(x86\)%\\\\Google\\\\Cloud SDK\\\\google-cloud-sdk\\\\bin'
            $sets | Should -Match '(?s)wingetPathEntries\s*=\s*\{.*?google-cloud-sdk\s*=\s*\[.*?%LOCALAPPDATA%\\\\Google\\\\Cloud SDK\\\\google-cloud-sdk\\\\bin'
        }

        It 'should generate Google.CloudSDK install timeout and gcloud PATH entry' {
            $json = Get-Content -LiteralPath $script:wingetJsonPath -Raw | ConvertFrom-Json
            $wingetSource = @($json.Sources | Where-Object { $_.SourceDetails.Name -eq 'winget' }) | Select-Object -First 1
            $package = @($wingetSource.Packages | Where-Object { $_.PackageIdentifier -eq 'Google.CloudSDK' }) | Select-Object -First 1

            $package | Should -Not -BeNullOrEmpty
            $package.installTimeoutSeconds | Should -Be 900
            @($package.pathEntries) | Should -Contain '%ProgramFiles%\Google\Cloud SDK\google-cloud-sdk\bin'
            @($package.pathEntries) | Should -Contain '%ProgramFiles(x86)%\Google\Cloud SDK\google-cloud-sdk\bin'
            @($package.pathEntries) | Should -Contain '%LOCALAPPDATA%\Google\Cloud SDK\google-cloud-sdk\bin'
            $package.verifyCommand.command | Should -Be 'gcloud'
            @($package.verifyCommand.args) | Should -Contain 'version'
        }
    }

    Context '1Password CLI package' {
        It 'should define the real op package directory in the SSOT before winget verification' {
            $sets = Get-Content -LiteralPath $script:setsPath -Raw

            $sets | Should -Match '(?s)wingetPathEntries\s*=\s*\{.*?_1password-cli\s*=\s*\[.*?%LOCALAPPDATA%\\\\Microsoft\\\\WinGet\\\\Packages\\\\AgileBits\.1Password\.CLI\*'
            $sets | Should -Not -Match '(?s)wingetPortableLinksById\s*=\s*\{.*?_1password-cli\s*=\s*\{.*?linkName\s*=\s*"op\.exe"'
        }

        It 'should generate op package path metadata into winget packages.json' {
            $json = Get-Content -LiteralPath $script:wingetJsonPath -Raw | ConvertFrom-Json
            $wingetSource = @($json.Sources | Where-Object { $_.SourceDetails.Name -eq 'winget' }) | Select-Object -First 1
            $package = @($wingetSource.Packages | Where-Object { $_.PackageIdentifier -eq 'AgileBits.1Password.CLI' }) | Select-Object -First 1

            $package | Should -Not -BeNullOrEmpty
            @($package.pathEntries) | Should -Contain '%LOCALAPPDATA%\Microsoft\WinGet\Packages\AgileBits.1Password.CLI*'
            $package.PSObject.Properties.Name | Should -Not -Contain 'portableLink'
            $package.verifyCommand.command | Should -Be 'op'
            @($package.verifyCommand.args) | Should -Contain '--version'
        }
    }

    Context 'Codex CLI package' {
        It 'should define Codex portable link metadata in the SSOT before winget verification' {
            $sets = Get-Content -LiteralPath $script:setsPath -Raw

            $sets | Should -Match '(?s)wingetPortableLinksById\s*=\s*\{.*?"OpenAI\.Codex"\s*=\s*\{.*?linkName\s*=\s*"codex\.exe".*?targetPattern\s*=\s*"codex-x86_64-pc-windows-msvc\.exe"'
        }

        It 'should generate Codex portable link metadata into winget packages.json' {
            $json = Get-Content -LiteralPath $script:wingetJsonPath -Raw | ConvertFrom-Json
            $wingetSource = @($json.Sources | Where-Object { $_.SourceDetails.Name -eq 'winget' }) | Select-Object -First 1
            $package = @($wingetSource.Packages | Where-Object { $_.PackageIdentifier -eq 'OpenAI.Codex' }) | Select-Object -First 1

            $package | Should -Not -BeNullOrEmpty
            $package.portableLink.linkName | Should -Be 'codex.exe'
            $package.portableLink.targetPattern | Should -Be 'codex-x86_64-pc-windows-msvc.exe'
            $package.verifyCommand.command | Should -Be 'codex'
            @($package.verifyCommand.args) | Should -Contain '--version'
        }
    }

    Context 'StyLua package' {
        It 'should generate StyLua with command verification' {
            $json = Get-Content -LiteralPath $script:wingetJsonPath -Raw | ConvertFrom-Json
            $wingetSource = @($json.Sources | Where-Object { $_.SourceDetails.Name -eq 'winget' }) | Select-Object -First 1
            $package = @($wingetSource.Packages | Where-Object { $_.PackageIdentifier -eq 'JohnnyMorganz.StyLua' }) | Select-Object -First 1

            $package | Should -Not -BeNullOrEmpty
            $package.verifyCommand.command | Should -Be 'stylua'
            @($package.verifyCommand.args) | Should -Contain '--version'
        }
    }

    Context 'Codex Desktop Microsoft Store package' {
        It 'should include Codex Desktop as a Windows-only Microsoft Store package in the SSOT' {
            $sets = Get-Content -LiteralPath $script:setsPath -Raw

            $sets | Should -Match '(?s)windowsOnly\s*=\s*\{.*?msstore\s*=\s*\[.*?"9PLM9XGG6VKS".*?\]'
        }

        It 'should define Codex Desktop AppX launch target verification in the SSOT' {
            $sets = Get-Content -LiteralPath $script:setsPath -Raw

            $sets | Should -Match '(?s)msstoreVerifyById\s*=\s*\{.*?"9PLM9XGG6VKS"\s*=\s*\{.*?type\s*=\s*"appxLaunchTarget".*?command\s*=\s*"OpenAI\.Codex".*?args\s*=\s*\[\s*"OpenAI\.Codex_2p2nqsd0c76g0!App"\s*\]'
        }

        It 'should skip Codex Desktop live Store install in the CI smoke test' {
            $sets = Get-Content -LiteralPath $script:setsPath -Raw

            $sets | Should -Match '(?s)wingetCiSkipInstall\s*=\s*\{.*?"9PLM9XGG6VKS"\s*=\s*true;'
        }

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
        It 'should define devcontainer with both Nix and Windows npm package mappings in the SSOT' {
            $sets = Get-Content -LiteralPath $script:setsPath -Raw

            $sets | Should -Match '(?s)devcontainer\s*=\s*\{.*?pkg\s*=\s*pkgs\.devcontainer;.*?npm\s*=\s*"@devcontainers/cli"'
            $sets | Should -Match '(?s)npmVerify\s*=\s*\{.*?devcontainer\s*=\s*\{.*?command\s*=\s*"devcontainer".*?args\s*=\s*\[\s*"--version"\s*\]'
        }

        It 'should generate @devcontainers/cli into the Windows npm package catalog with verification' {
            $json = Get-Content -LiteralPath $script:npmJsonPath -Raw | ConvertFrom-Json
            $package = @($json.globalPackages | Where-Object { $_.name -eq '@devcontainers/cli' }) | Select-Object -First 1

            $package | Should -Not -BeNullOrEmpty
            $package.verifyCommand.command | Should -Be 'devcontainer'
            @($package.verifyCommand.args) | Should -Contain '--version'
        }

        It 'should have winget-export generate npm packages.json from the SSOT' {
            $exporter = Get-Content -LiteralPath (Join-Path $script:repoRoot "nix/packages/winget.nix") -Raw

            $exporter | Should -Match 'windows/npm/packages\.json'
            $exporter | Should -Match 'npmFromMap'
            $exporter | Should -Match '\$out/npm/packages\.json'
        }
    }

    Context 'Windows Orca and Python installation policy' {
        It 'should manage Orca as a Windows-only winget package and avoid native Python winget installs in the SSOT' {
            $sets = Get-Content -LiteralPath $script:setsPath -Raw

            $sets | Should -Match '(?s)windowsOnly\s*=\s*\{.*?winget\s*=\s*\[.*?"StablyAI\.Orca".*?\]'
            $sets | Should -Match '(?s)wingetCiSkipInstall\s*=\s*\{.*?"StablyAI\.Orca"\s*=\s*true;'
            $sets | Should -Match '(?s)python3\s*=\s*\{.*?pkg\s*=\s*pkgs\.python3;.*?winget\s*=\s*null;'
            $sets | Should -Not -Match 'winget\s*=\s*"Python\.Python\.3\.13"'
            $sets | Should -Match '(?s)uv\s*=\s*\{.*?pkg\s*=\s*pkgs\.uv;.*?winget\s*=\s*"astral-sh\.uv"'
        }

        It 'should generate Orca and uv without the native Python winget package' {
            $json = Get-Content -LiteralPath $script:wingetJsonPath -Raw | ConvertFrom-Json
            $wingetSource = @($json.Sources | Where-Object { $_.SourceDetails.Name -eq 'winget' }) | Select-Object -First 1
            $orca = @($wingetSource.Packages | Where-Object { $_.PackageIdentifier -eq 'StablyAI.Orca' }) | Select-Object -First 1
            $python = @($wingetSource.Packages | Where-Object { $_.PackageIdentifier -eq 'Python.Python.3.13' }) | Select-Object -First 1
            $uv = @($wingetSource.Packages | Where-Object { $_.PackageIdentifier -eq 'astral-sh.uv' }) | Select-Object -First 1

            $orca | Should -Not -BeNullOrEmpty
            $orca.ciSkipInstall | Should -BeTrue
            $python | Should -BeNullOrEmpty -Because "Windows Python should be provisioned through uv, not the native winget package"
            $uv | Should -Not -BeNullOrEmpty
            $uv.verifyCommand.command | Should -Be 'uv'
            @($uv.verifyCommand.args) | Should -Contain '--version'
        }
    }

    Context 'Windows native Rust browser automation tools' {
        It 'should manage agent-browser as a Windows npm global package with verification' {
            $sets = Get-Content -LiteralPath $script:setsPath -Raw

            $sets | Should -Match '(?s)windowsOnly\s*=\s*\{.*?npm\s*=\s*\[.*?"agent-browser@0\.29\.1".*?\]'
            $sets | Should -Match '(?s)npmVerify\s*=\s*\{.*?"agent-browser"\s*=\s*\{.*?command\s*=\s*"agent-browser".*?args\s*=\s*\[\s*"--version"\s*\]'
        }

        It 'should generate agent-browser into the Windows npm package catalog with verification' {
            $json = Get-Content -LiteralPath $script:npmJsonPath -Raw | ConvertFrom-Json
            $package = @($json.globalPackages | Where-Object { $_.name -eq 'agent-browser@0.29.1' }) | Select-Object -First 1

            $package | Should -Not -BeNullOrEmpty
            $package.verifyCommand.command | Should -Be 'agent-browser'
            @($package.verifyCommand.args) | Should -Contain '--version'
        }

        It 'should include Visual Studio Build Tools with C++ workload install metadata in the SSOT' {
            $sets = Get-Content -LiteralPath $script:setsPath -Raw

            $sets | Should -Match '(?s)windowsOnly\s*=\s*\{.*?winget\s*=\s*\[.*?"Microsoft\.VisualStudio\.2022\.BuildTools".*?\]'
            $sets | Should -Match '(?s)wingetInstallArgs\s*=\s*\{.*?"Microsoft\.VisualStudio\.2022\.BuildTools"\s*=\s*\[.*?"--override".*?"--add Microsoft\.VisualStudio\.Workload\.VCTools --includeRecommended --passive --wait --norestart"'
            $sets | Should -Match '(?s)wingetInstallTimeoutSeconds\s*=\s*\{.*?"Microsoft\.VisualStudio\.2022\.BuildTools"\s*=\s*1800'
        }

        It 'should generate Visual Studio Build Tools with C++ workload install metadata' {
            $json = Get-Content -LiteralPath $script:wingetJsonPath -Raw | ConvertFrom-Json
            $wingetSource = @($json.Sources | Where-Object { $_.SourceDetails.Name -eq 'winget' }) | Select-Object -First 1
            $package = @($wingetSource.Packages | Where-Object { $_.PackageIdentifier -eq 'Microsoft.VisualStudio.2022.BuildTools' }) | Select-Object -First 1

            $package | Should -Not -BeNullOrEmpty
            @($package.installArgs) | Should -Contain '--override'
            @($package.installArgs) | Should -Contain '--add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --passive --wait --norestart'
            $package.installTimeoutSeconds | Should -Be 1800
        }
    }
}
