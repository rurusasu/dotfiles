#Requires -Module Pester

BeforeDiscovery {
    $script:featureCases = @(
        @{ Feature = 'WithDocker'; PackageId = 'Docker.DockerDesktop' }
        @{ Feature = 'WithHermes'; PackageId = 'Google.Chrome' }
        @{ Feature = 'WithOllama'; PackageId = 'Ollama.Ollama' }
    )
}

BeforeAll {
    . $PSScriptRoot/../../lib/SetupHandler.ps1
    . $PSScriptRoot/../../lib/Invoke-ExternalCommand.ps1
    . $PSScriptRoot/../../handlers/Handler.Winget.ps1

    $script:featurePackages = @(
        [PSCustomObject]@{ PackageIdentifier = 'Docker.DockerDesktop'; installFeature = 'WithDocker' }
        [PSCustomObject]@{ PackageIdentifier = 'Google.Chrome'; installFeature = 'WithHermes' }
        [PSCustomObject]@{ PackageIdentifier = 'Ollama.Ollama'; installFeature = 'WithOllama' }
        [PSCustomObject]@{ PackageIdentifier = 'Example.AlwaysInstalled' }
    )

}

Describe 'WingetHandler feature gates at the install boundary' {
    BeforeEach {
        $script:handler = [WingetHandler]::new()
        $repoFixture = Join-Path $TestDrive 'dotfiles'
        $wingetFixture = Join-Path $repoFixture 'windows/winget'
        New-Item -ItemType Directory -Path $wingetFixture -Force | Out-Null

        $manifestFixture = @{
            Sources = @(
                @{
                    SourceDetails = @{ Name = 'winget' }
                    Packages = $script:featurePackages
                }
            )
        } | ConvertTo-Json -Depth 8
        Set-Content -LiteralPath (Join-Path $wingetFixture 'packages.json') -Value $manifestFixture -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $wingetFixture 'retired-packages.json') -Value '{"packages":[]}' -Encoding UTF8

        $script:ctx = [SetupContext]::new($repoFixture)
        $script:ctx.Options['WithDocker'] = $false
        $script:ctx.Options['WithHermes'] = $false
        $script:ctx.Options['WithOllama'] = $false
        $script:installedPackageIds = @()

        Mock Invoke-Winget {
            param([string[]]$Arguments)

            if ($Arguments -contains 'install') {
                $idIndex = [Array]::IndexOf($Arguments, '--id')
                if ($idIndex -ge 0 -and ($idIndex + 1) -lt $Arguments.Count) {
                    $script:installedPackageIds += [string]$Arguments[$idIndex + 1]
                }
                $global:LASTEXITCODE = 0
                return @()
            }

            # Empty list output means none of the fixture packages is installed.
            $global:LASTEXITCODE = 1
            return @()
        }
        Mock Write-Host { }
    }

    It 'excludes <PackageId> from installation when <Feature> is disabled' -ForEach $script:featureCases {
        param($Feature, $PackageId)

        $result = $script:handler.Apply($script:ctx)

        $result.Success | Should -BeTrue
        $script:installedPackageIds | Should -Contain 'Example.AlwaysInstalled'
        $script:installedPackageIds | Should -Not -Contain $PackageId
    }

    It 'includes <PackageId> in installation when <Feature> is enabled' -ForEach $script:featureCases {
        param($Feature, $PackageId)
        $script:ctx.Options[$Feature] = $true

        $result = $script:handler.Apply($script:ctx)

        $result.Success | Should -BeTrue
        $script:installedPackageIds | Should -Contain 'Example.AlwaysInstalled'
        $script:installedPackageIds | Should -Contain $PackageId
    }
}
