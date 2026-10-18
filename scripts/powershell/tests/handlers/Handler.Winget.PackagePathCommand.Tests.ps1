BeforeAll {
    . $PSScriptRoot/../../lib/SetupHandler.ps1
    . $PSScriptRoot/../../handlers/Handler.Winget.ps1
}

Describe 'WingetHandler declared package command verification' {
    BeforeEach {
        $script:originalPath = $env:PATH
        $script:declaredDirectory = Join-Path $TestDrive 'MinGit\cmd'
        $script:shadowDirectory = Join-Path $TestDrive 'CodexCache\bin'
        New-Item -ItemType Directory -Path $script:declaredDirectory, $script:shadowDirectory -Force | Out-Null
        $script:declaredExecutable = Join-Path $script:declaredDirectory 'git.exe'
        Set-Content -LiteralPath $script:declaredExecutable -Value 'MinGit fixture'
        Set-Content -LiteralPath (Join-Path $script:shadowDirectory 'git.exe') -Value 'unrelated Git fixture'
        $env:PATH = "$($script:shadowDirectory);$env:PATH"
        $script:verifiedCommands = [Collections.Generic.List[string]]::new()
        $script:verificationExitCode = 0
        Mock Invoke-VerifyCommand {
            param($Command)
            $script:verifiedCommands.Add([string]$Command)
            $global:LASTEXITCODE = $script:verificationExitCode
            return 'git fixture version'
        }
        Mock Write-Host { }
        $script:package = [pscustomobject]@{
            PathEntries   = @($script:declaredDirectory)
            VerifyCommand = [pscustomobject]@{ type = 'pathEntriesCommand'; command = 'git'; args = @('--version') }
        }
        $script:handler = [WingetHandler]::new()
    }

    AfterEach { $env:PATH = $script:originalPath }

    It 'should verify the declared MinGit executable even when an unrelated Git shadows PATH' {
        $script:handler.TestPackageVerificationForPackage($script:package, $false) | Should -BeTrue

        @($script:verifiedCommands) | Should -Be @($script:declaredExecutable)
    }

    It 'should reject a missing package executable instead of accepting an unrelated PATH command' {
        Remove-Item -LiteralPath $script:declaredExecutable

        $script:handler.TestPackageVerificationForPackage($script:package, $false) | Should -BeFalse

        $script:verifiedCommands.Count | Should -Be 0
    }

    It 'should retain a declared executable failure instead of falling back to unrelated Git' {
        $script:verificationExitCode = 7

        $script:handler.TestPackageVerificationForPackage($script:package, $false) | Should -BeFalse

        @($script:verifiedCommands) | Should -Be @($script:declaredExecutable)
    }

    It 'should retain normal PATH lookup for existing command verifiers' {
        $script:package.VerifyCommand.type = 'command'

        $script:handler.TestPackageVerificationForPackage($script:package, $false) | Should -BeTrue

        @($script:verifiedCommands) | Should -Be @('git')
    }
}
