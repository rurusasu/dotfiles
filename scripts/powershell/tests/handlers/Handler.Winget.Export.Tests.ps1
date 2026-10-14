BeforeAll {
    Set-StrictMode -Version Latest
    . $PSScriptRoot/../../lib/SetupHandler.ps1
    . $PSScriptRoot/../../lib/Invoke-ExternalCommand.ps1
    . $PSScriptRoot/../../handlers/Handler.Winget.ps1
}

Describe 'WingetHandler declarative direct source export' {
    BeforeEach {
        $script:repository = Join-Path $TestDrive 'repository'
        $script:manifestDirectory = Join-Path $script:repository 'windows/winget'
        New-Item -ItemType Directory -Path $script:manifestDirectory -Force | Out-Null
        $script:manifestPath = Join-Path $script:manifestDirectory 'packages.json'
        $script:originalManifest = @'
{"Sources":[{"SourceDetails":{"Name":"winget"},"Packages":[{"PackageIdentifier":"Old.Package"}]},{"SourceDetails":{"Name":"direct","Identifier":"Dotfiles.DirectInstallers","Type":"Dotfiles.DirectInstaller","Argument":"https://example.invalid"},"Packages":[{"PackageIdentifier":"Example.Dia","installTimeoutSeconds":73,"verifyCommand":{"type":"appxLaunchTarget","command":"Example.Dia","args":["Example.Dia_fixture!Dia"]},"directInstaller":{"type":"appx","name":"Example.Dia","packageFamilyName":"Example.Dia_fixture","publisher":"CN=Fixture","version":"1.1.0.6","architecture":"x64","executable":"Dia.exe","url":"https://example.invalid/Dia.msix","sha256":"abababababababababababababababababababababababababababababababab","dependencies":[{"url":"https://example.invalid/vclibs.appx","sha256":"cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd"}]}}]}]}
'@
        [IO.File]::WriteAllText($script:manifestPath, $script:originalManifest)
        $script:exportedJson = '{"Sources":[{"SourceDetails":{"Name":"winget","Identifier":"Microsoft.Winget.Source_8wekyb3d8bbwe","Type":"Microsoft.PreIndexed.Package","Argument":"https://cdn.winget.microsoft.com/cache"},"Packages":[{"PackageIdentifier":"New.Package","Version":"2.0.0"}]}]}'
        $script:exportExitCode = 0
        $script:exportPath = $null
        $script:writeExport = $true
        $script:manifestDuringExport = $null
        $script:handler = [WingetHandler]::new()
        $script:context = [SetupContext]::new($script:repository)
        $script:context.Options['WingetMode'] = 'export'
        Mock Write-Host {}
        Mock Invoke-Winget {
            param($Arguments)
            $script:exportPath = $Arguments[2]
            $script:manifestDuringExport = if ([IO.File]::Exists($script:manifestPath)) { [IO.File]::ReadAllText($script:manifestPath) } else { $null }
            if ($script:writeExport) { [IO.File]::WriteAllText($script:exportPath, $script:exportedJson) }
            $global:LASTEXITCODE = $script:exportExitCode
        }
    }

    It 'should preserve the complete declarative direct source while replacing WinGet inventory' {
        $result = $script:handler.Apply($script:context)
        $result.Success | Should -BeTrue -Because $result.Message
        $exported = Get-Content -LiteralPath $script:manifestPath -Raw | ConvertFrom-Json
        $exported.Sources[0].Packages[0].PackageIdentifier | Should -Be 'New.Package'
        $exported.Sources[0].Packages[0].Version | Should -Be '2.0.0'
        $direct = @($exported.Sources | Where-Object { $_.SourceDetails.Name -eq 'direct' })
        $direct.Count | Should -Be 1
        $expectedDirect = ($script:originalManifest | ConvertFrom-Json).Sources[1] | ConvertTo-Json -Depth 20 -Compress
        ($direct[0] | ConvertTo-Json -Depth 20 -Compress) | Should -Be $expectedDirect
        $script:manifestDuringExport | Should -Be $script:originalManifest
        $script:exportPath | Should -Not -Be $script:manifestPath
        [IO.File]::Exists($script:exportPath) | Should -BeFalse
    }

    It 'should preserve the original manifest after a failed WinGet export' {
        $script:exportExitCode = 7
        $result = $script:handler.Apply($script:context)
        $result.Success | Should -BeFalse
        [IO.File]::ReadAllText($script:manifestPath) | Should -Be $script:originalManifest
        [IO.File]::Exists($script:exportPath) | Should -BeFalse
    }

    It 'should preserve the original manifest after successful export with <Fault>' -TestCases @(
        @{ Fault = 'invalid JSON'; Json = '{' }
        @{ Fault = 'missing Sources'; Json = '{}' }
        @{ Fault = 'nonarray Sources'; Json = '{"Sources":{}}' }
        @{ Fault = 'invalid source name'; Json = '{"Sources":[{"SourceDetails":{"Name":""},"Packages":[]}]}' }
        @{ Fault = 'invalid package ID'; Json = '{"Sources":[{"SourceDetails":{"Name":"winget"},"Packages":[{"PackageIdentifier":""}]}]}' }
        @{ Fault = 'missing output'; Json = $null }
    ) {
        param($Fault, $Json)
        $script:exportedJson = $Json
        $script:writeExport = $Fault -ne 'missing output'
        $result = $script:handler.Apply($script:context)
        $result.Success | Should -BeFalse
        [IO.File]::ReadAllText($script:manifestPath) | Should -Be $script:originalManifest
        [IO.File]::Exists($script:exportPath) | Should -BeFalse
    }

    It 'should export ordinary WinGet inventory without a direct source' {
        [IO.File]::WriteAllText($script:manifestPath, '{"Sources":[]}')
        $result = $script:handler.Apply($script:context)
        $result.Success | Should -BeTrue -Because $result.Message
        $exported = Get-Content -LiteralPath $script:manifestPath -Raw | ConvertFrom-Json
        @($exported.Sources).Count | Should -Be 1
        $exported.Sources[0].Packages[0].PackageIdentifier | Should -Be 'New.Package'
    }

    It 'should create an ordinary WinGet manifest when no original exists' {
        Remove-Item -LiteralPath $script:manifestPath
        $result = $script:handler.Apply($script:context)
        $result.Success | Should -BeTrue -Because $result.Message
        $exported = Get-Content -LiteralPath $script:manifestPath -Raw | ConvertFrom-Json
        $exported.Sources[0].Packages[0].PackageIdentifier | Should -Be 'New.Package'
    }
}
