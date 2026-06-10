#Requires -Module Pester

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    $script:setsPath = Join-Path $script:repoRoot "nix/packages/sets.nix"
    $script:wingetJsonPath = Join-Path $script:repoRoot "windows/winget/packages.json"
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

        It 'should cap Warp install time so install.cmd cannot hang indefinitely' {
            $json = Get-Content -LiteralPath $script:wingetJsonPath -Raw | ConvertFrom-Json
            $wingetSource = @($json.Sources | Where-Object { $_.SourceDetails.Name -eq 'winget' }) | Select-Object -First 1
            $warp = @($wingetSource.Packages | Where-Object { $_.PackageIdentifier -eq 'Warp.Warp' }) | Select-Object -First 1

            $warp.installTimeoutSeconds | Should -Be 900
        }

        It 'should update flake inputs in the Nix rebuild aliases before applying the system' {
            $wslUsers = Get-Content -LiteralPath (Join-Path $script:repoRoot "nix/home/wsl/users.nix") -Raw
            $linuxUsers = Get-Content -LiteralPath (Join-Path $script:repoRoot "nix/home/linux/users.nix") -Raw

            $wslUsers | Should -Match 'nrs\s*=\s*"nix flake update ~/.dotfiles && sudo nixos-rebuild switch --flake ~/.dotfiles --impure'
            $linuxUsers | Should -Match 'nrs\s*=\s*"nix flake update ~/.dotfiles && sudo nixos-rebuild switch --flake ~/.dotfiles --impure'
        }

        It 'should update flake inputs before every scripted NixOS rebuild entry point' {
            $taskfile = Get-Content -LiteralPath (Join-Path $script:repoRoot "Taskfile.yml") -Raw
            $updateScript = Get-Content -LiteralPath (Join-Path $script:repoRoot "scripts/sh/update.sh") -Raw
            $postInstallScript = Get-Content -LiteralPath (Join-Path $script:repoRoot "scripts/sh/nixos-wsl-postinstall.sh") -Raw

            $taskfile | Should -Match 'nix flake update && sudo nixos-rebuild switch --flake \. --impure'
            $updateScript | Should -Match 'nix flake update ~/.dotfiles'
            $postInstallScript | Should -Match 'nix flake update "\$TARGET_DIR"'
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
}
