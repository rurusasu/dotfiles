BeforeAll {
    . $PSScriptRoot/../../lib/SetupHandler.ps1
    . $PSScriptRoot/../../handlers/Handler.Winget.ps1
    $script:repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'))
}

Describe 'WingetHandler package PATH persistence' {
    BeforeEach {
        $script:originalPath = $env:PATH
        $script:originalLocalAppData = $env:LOCALAPPDATA
        $env:LOCALAPPDATA = Join-Path $TestDrive 'LocalAppData'
        $env:PATH = "$env:SystemRoot\System32"
        $script:linksDirectory = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links'
        $packageDirectory = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages\Starship.Starship_fixture'
        $script:ordinaryDirectory = Join-Path $TestDrive 'ordinary-bin'
        New-Item -ItemType Directory -Path $packageDirectory, $script:ordinaryDirectory, $script:linksDirectory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $packageDirectory 'starship.exe') -Value 'portable fixture'

        $manifest = Get-Content -LiteralPath (Join-Path $script:repositoryRoot 'windows/winget/packages.json') -Raw | ConvertFrom-Json
        $script:starshipEntry = $manifest.Sources.Packages | Where-Object PackageIdentifier -EQ 'Starship.Starship'
        $script:starshipEntry | Add-Member -NotePropertyName persistPathEntries -NotePropertyValue $true -Force
        $script:caseManifest = [pscustomobject]@{
            Sources = @([pscustomobject]@{
                    SourceDetails = [pscustomobject]@{ Name = 'winget' }
                    Packages      = @($script:starshipEntry, [pscustomobject]@{
                            PackageIdentifier = 'Ordinary.Tool'
                            pathEntries       = @($script:ordinaryDirectory)
                            verifyCommand     = [pscustomobject]@{ command = 'ordinary-tool'; args = @('--version') }
                        })
                })
        }
        $script:initialUserPath = 'C:\retained-first;C:\retained-second'
        $script:userPathStore = $script:initialUserPath
        $script:userPathWrites = 0
        Mock Get-UserEnvironmentPath { return $script:userPathStore }
        Mock Set-UserEnvironmentPath {
            param($Path)
            $script:userPathStore = $Path
            $script:userPathWrites++
        }
        Mock Get-ExternalCommand { return @{ Source = 'C:\winget.exe' } }
        Mock Test-PathExist { return $true }
        Mock Get-JsonContent { return $script:caseManifest }
        Mock Update-ProcessEnvironmentPath { }
        Mock Invoke-Winget {
            param($Arguments)
            $global:LASTEXITCODE = if ($Arguments -contains 'list') { 1 } else { 0 }
        }
        Mock Invoke-VerifyCommand { $global:LASTEXITCODE = 0; return 'fixture version 1.0' }
        Mock New-Item { throw 'Fixture disallows symlinks' } -ParameterFilter { $ItemType -eq 'SymbolicLink' }
        Mock Write-Host { }
        $script:handler = [WingetHandler]::new()
        $script:context = [SetupContext]::new($TestDrive)
        $script:context.Options['SkipRetiredPackageCleanup'] = $true
        $script:context.Options['WingetProcessOnlyPath'] = $true
    }

    AfterEach {
        $env:PATH = $script:originalPath
        $env:LOCALAPPDATA = $script:originalLocalAppData
    }

    It 'should persist only the explicitly opted-in helper directory during the GUI phase' {
        $result = $script:handler.Apply($script:context)

        $result.Success | Should -BeTrue -Because $result.Message
        $script:userPathStore | Should -Be "$($script:initialUserPath);$($script:linksDirectory)"
        $script:userPathStore -split ';' | Should -Not -Contain $script:ordinaryDirectory
        $env:PATH -split ';' | Should -Contain $script:ordinaryDirectory
        Test-Path -LiteralPath (Join-Path $script:linksDirectory 'starship.exe') -PathType Leaf | Should -BeTrue
        $script:userPathWrites | Should -Be 1
    }

    It 'should keep omitted false or nonboolean opt-in metadata process-only (<Setting>)' -TestCases @(
        @{ Setting = 'omitted'; Value = $null }
        @{ Setting = 'false'; Value = $false }
        @{ Setting = 'nonboolean'; Value = 'true' }
    ) {
        param($Setting, $Value)
        if ($Setting -eq 'omitted') { $script:starshipEntry.PSObject.Properties.Remove('persistPathEntries') }
        else { $script:starshipEntry.persistPathEntries = $Value }

        $result = $script:handler.Apply($script:context)

        $result.Success | Should -BeTrue -Because $result.Message
        $script:userPathStore | Should -Be $script:initialUserPath
        $script:userPathWrites | Should -Be 0
        $env:PATH -split ';' | Should -Contain $script:linksDirectory
        $env:PATH -split ';' | Should -Contain $script:ordinaryDirectory
    }

    It 'should avoid duplicate directory entries and writes when applied twice' {
        $script:handler.Apply($script:context).Success | Should -BeTrue
        $script:handler.Apply($script:context).Success | Should -BeTrue

        @($script:userPathStore -split ';' | Where-Object { $_ -eq $script:linksDirectory }).Count | Should -Be 1
        @($env:PATH -split ';' | Where-Object { $_ -eq $script:linksDirectory }).Count | Should -Be 1
        @($env:PATH -split ';' | Where-Object { $_ -eq $script:ordinaryDirectory }).Count | Should -Be 1
        $script:userPathWrites | Should -Be 1
    }

    It 'should retain ordinary GUI process-only behavior with an oversized persisted User PATH' {
        $script:starshipEntry.persistPathEntries = $false
        $script:userPathStore = 'C:\missing;' * 4000
        $originalUserPath = $script:userPathStore
        $originalUserPath.Length | Should -BeGreaterThan 32767

        $result = $script:handler.Apply($script:context)

        $result.Success | Should -BeTrue -Because $result.Message
        $script:userPathStore | Should -Be $originalUserPath
        $script:userPathWrites | Should -Be 0
        $env:PATH -split ';' | Should -Contain $script:ordinaryDirectory
    }

    It 'should retain ordinary package persistence outside the process-only profile' {
        $script:context.Options['WingetProcessOnlyPath'] = $false

        $script:handler.Apply($script:context).Success | Should -BeTrue

        $script:userPathStore -split ';' | Should -Contain $script:linksDirectory
        $script:userPathStore -split ';' | Should -Contain $script:ordinaryDirectory
    }
}
