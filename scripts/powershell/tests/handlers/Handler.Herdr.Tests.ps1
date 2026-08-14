#Requires -Module Pester

BeforeAll {
    . $PSScriptRoot/../../lib/SetupHandler.ps1
    . $PSScriptRoot/../../lib/Invoke-ExternalCommand.ps1
    . $PSScriptRoot/../../handlers/Handler.Herdr.ps1
    $script:projectRoot = (Resolve-Path -LiteralPath "$PSScriptRoot/../../../..").Path
}

Describe 'HerdrHandler' {
    BeforeEach {
        $script:handler = [HerdrHandler]::new()
        $script:ctx = [SetupContext]::new($script:projectRoot)
        Mock Write-Host { }
    }

    It 'has user-scope Phase 1 metadata' {
        $handler.Name | Should -Be 'Herdr'
        $handler.Description | Should -Not -BeNullOrEmpty
        $handler.Order | Should -Be 8
        $handler.RequiresAdmin | Should -BeFalse
        $handler.Phase | Should -Be 1
    }

    It 'can apply the official installer without probing external state' {
        $handler.CanApply($ctx) | Should -BeTrue
    }

    It 'downloads and executes the official Windows preview installer' {
        Mock Invoke-RestMethod { '# test installer' }
        Mock Get-ExternalCommand {
            [PSCustomObject]@{ Source = 'C:\Users\test\.herdr\current\herdr.exe' }
        } -ParameterFilter { $Name -eq 'herdr' }
        Mock Invoke-VerifyCommand {
            $global:LASTEXITCODE = 0
            'herdr 0.8.0'
        }

        $result = $handler.Apply($ctx)

        $result.Success | Should -BeTrue
        Should -Invoke Invoke-RestMethod -Times 1 -ParameterFilter {
            $Uri -eq 'https://herdr.dev/install.ps1'
        }
        Should -Invoke Invoke-VerifyCommand -Times 1 -ParameterFilter {
            $Command -eq 'C:\Users\test\.herdr\current\herdr.exe' -and
            $Arguments -contains '--version'
        }
    }

    It 'returns failure when the official installer fails' {
        Mock Invoke-RestMethod { throw 'network failure' }

        $result = $handler.Apply($ctx)

        $result.Success | Should -BeFalse
        $result.Message | Should -Match 'Herdr'
    }

    It 'returns failure when version verification fails' {
        Mock Invoke-RestMethod { '# test installer' }
        Mock Get-ExternalCommand {
            [PSCustomObject]@{ Source = 'C:\Users\test\.herdr\current\herdr.exe' }
        } -ParameterFilter { $Name -eq 'herdr' }
        Mock Invoke-VerifyCommand {
            $global:LASTEXITCODE = 1
            'version failure'
        }

        $result = $handler.Apply($ctx)

        $result.Success | Should -BeFalse
        $result.Message | Should -Match '検証'
    }

    It 'verifies the official managed path when the current process PATH is stale' {
        $previousLocalAppData = $env:LOCALAPPDATA
        $env:LOCALAPPDATA = Join-Path $TestDrive 'AppData/Local'
        $managedPath = Join-Path $env:LOCALAPPDATA 'Programs\Herdr\bin\herdr.exe'
        New-Item -ItemType Directory -Path (Split-Path -Parent $managedPath) -Force | Out-Null
        New-Item -ItemType File -Path $managedPath -Force | Out-Null

        Mock Invoke-RestMethod { '# test installer' }
        Mock Get-ExternalCommand { $null } -ParameterFilter { $Name -eq 'herdr' }
        Mock Invoke-VerifyCommand {
            $global:LASTEXITCODE = 0
            'herdr 0.8.0'
        }

        try {
            $result = $handler.Apply($ctx)

            $result.Success | Should -BeTrue -Because $result.Message
            Should -Invoke Invoke-VerifyCommand -Times 1 -ParameterFilter {
                $Command -eq $managedPath -and
                $Arguments -contains '--version'
            }
        }
        finally {
            $env:LOCALAPPDATA = $previousLocalAppData
        }
    }
}
