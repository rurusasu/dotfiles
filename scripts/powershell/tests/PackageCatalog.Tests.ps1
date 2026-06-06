#Requires -Module Pester

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    $script:setsPath = Join-Path $script:repoRoot "nix/packages/sets.nix"
    $script:wingetJsonPath = Join-Path $script:repoRoot "windows/winget/packages.json"
}

Describe 'Package catalog consistency' {
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

        It 'should generate Codex Desktop under the msstore source with launch target verification' {
            $json = Get-Content -LiteralPath $script:wingetJsonPath -Raw | ConvertFrom-Json
            $msstoreSource = @($json.Sources | Where-Object { $_.SourceDetails.Name -eq 'msstore' }) | Select-Object -First 1
            $package = @($msstoreSource.Packages | Where-Object { $_.PackageIdentifier -eq '9PLM9XGG6VKS' }) | Select-Object -First 1

            $package | Should -Not -BeNullOrEmpty
            $package.verifyCommand.type | Should -Be 'appxLaunchTarget'
            $package.verifyCommand.command | Should -Be 'OpenAI.Codex'
            @($package.verifyCommand.args) | Should -Contain 'OpenAI.Codex_2p2nqsd0c76g0!App'
        }
    }
}
