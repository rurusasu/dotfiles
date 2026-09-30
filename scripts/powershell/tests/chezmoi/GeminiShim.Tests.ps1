#Requires -Module Pester

Describe 'Windows Gemini shim bootstrap' {
    BeforeAll {
        $script:templatePath = Join-Path $PSScriptRoot '../../../../chezmoi/.chezmoiscripts/run_after_ensure-gemini-shim_windows.ps1.tmpl'
        $source = Get-Content -LiteralPath $script:templatePath -Raw
        $source = $source -replace '(?m)^\{\{ if eq \.chezmoi\.os "windows" -\}\}\r?\n', ''
        $source = $source -replace '(?m)^\{\{ end -\}\}\s*$', ''

        $script:testBin = Join-Path $TestDrive 'bin'
        New-Item -ItemType Directory -Path $script:testBin -Force | Out-Null
        $script:renderedScript = Join-Path $TestDrive 'ensure-gemini-shim.ps1'
        [System.IO.File]::WriteAllText($script:renderedScript, $source, [System.Text.UTF8Encoding]::new($false))
        $script:powerShellExe = (Get-Process -Id $PID).Path
    }

    It 'does not require pnpm root when the existing Gemini command is healthy' {
        $pnpmMarker = Join-Path $TestDrive 'pnpm-called.txt'
        $pnpmScript = Join-Path $script:testBin 'pnpm.ps1'
        $geminiScript = Join-Path $script:testBin 'gemini.ps1'
        [System.IO.File]::WriteAllText(
            $pnpmScript,
            "Set-Content -LiteralPath `$env:PNPM_TEST_MARKER -Value called`nexit 1`n",
            [System.Text.UTF8Encoding]::new($false)
        )
        [System.IO.File]::WriteAllText(
            $geminiScript,
            "Write-Output '0.61.0'`nexit 0`n",
            [System.Text.UTF8Encoding]::new($false)
        )

        $previousPath = $env:PATH
        $previousUserProfile = $env:USERPROFILE
        $previousMarker = $env:PNPM_TEST_MARKER
        try {
            $env:PATH = "$script:testBin;$env:SystemRoot\System32"
            $env:USERPROFILE = Join-Path $TestDrive 'user-home'
            $env:PNPM_TEST_MARKER = $pnpmMarker
            $output = @(& $script:powerShellExe -NoProfile -File $script:renderedScript 2>&1)
            $exitCode = $LASTEXITCODE
        }
        finally {
            $env:PATH = $previousPath
            $env:USERPROFILE = $previousUserProfile
            $env:PNPM_TEST_MARKER = $previousMarker
        }

        $exitCode | Should -Be 0
        ($output -join "`n") | Should -Match 'gemini command is healthy'
        Test-Path -LiteralPath $pnpmMarker | Should -BeFalse
    }
}

