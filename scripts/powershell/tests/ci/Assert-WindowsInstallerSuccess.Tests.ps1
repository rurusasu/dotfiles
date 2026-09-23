BeforeAll {
    $assertionPath = Join-Path $PSScriptRoot '../../ci/Assert-WindowsInstallerSuccess.ps1'
    if (Test-Path -LiteralPath $assertionPath) {
        . $assertionPath
    }
}

Describe 'Assert-WindowsInstallerSuccess' {
    It 'rejects a nonzero installer exit even when the completion marker is present' {
        {
            Assert-WindowsInstallerSuccess -Output 'User Phase Complete!' -ExitCode 37 -CompletionMarker 'User Phase Complete!'
        } | Should -Throw '*code 37*'
    }

    It 'rejects a fatal marker even when the process exits successfully' {
        $output = @'
[Npm] FAIL 1 package install failed
Total: 1 | Success: 0 | Failure: 1
User Phase Complete!
'@

        { Assert-WindowsInstallerSuccess -Output $output -ExitCode 0 -CompletionMarker 'User Phase Complete!' } |
            Should -Throw '*fatal or incomplete marker*'

        $crossMarkOutput = ('[Npm] ' + [char]0x2717 + ' agent-browser failed' + [Environment]::NewLine + 'User Phase Complete!')
        { Assert-WindowsInstallerSuccess -Output $crossMarkOutput -ExitCode 0 -CompletionMarker 'User Phase Complete!' } |
            Should -Throw '*fatal or incomplete marker*'
    }

    It 'does not let successful summaries and package markers hide a fatal install error' {
        $successMarker = '[Npm] ' + [string][char]0x2713 + ' agent-browser@0.38.1'
        $output = @"
Total: 2 | Success: 2 | Failure: 0
[Winget] FAIL a package install failed
$successMarker
User Phase Complete!
"@

        {
            Assert-WindowsInstallerSuccess `
                -Output $output `
                -ExitCode 0 `
                -CompletionMarker 'User Phase Complete!' `
                -RequiredOutputMarkers @($successMarker)
        } | Should -Throw '*fatal or incomplete marker*'
    }

    It 'rejects an incomplete setup summary even when no fatal marker is printed' {
        $output = @'
Total: 6 | Success: 2 | Failure: 4
User Phase Complete!
'@

        { Assert-WindowsInstallerSuccess -Output $output -ExitCode 0 -CompletionMarker 'User Phase Complete!' } |
            Should -Throw '*reported 4 failed handler*'
    }

    It 'requires the expected phase completion marker' {
        $output = 'Total: 1 | Success: 1 | Failure: 0'
        { Assert-WindowsInstallerSuccess -Output $output -ExitCode 0 -CompletionMarker 'User Phase Complete!' } |
            Should -Throw '*did not reach completion marker*'
    }

    It 'requires package-manager success markers so preinstalled commands cannot mask skipped installs' {
        $output = @'
Total: 2 | Success: 2 | Failure: 0
[Npm] CHECKMARK agent-browser@0.38.1
PNPM_SUCCESS
User Phase Complete!
'@
        $output = $output.Replace('CHECKMARK', [string][char]0x2713)
        $pnpmBootstrapMarker = '[Pnpm] ' + (ConvertFrom-Json '"npm \u3067 pnpm \u3092\u30a4\u30f3\u30b9\u30c8\u30fc\u30eb\u3057\u307e\u3057\u305f"')
        $output = $output.Replace('PNPM_SUCCESS', $pnpmBootstrapMarker)

        {
            Assert-WindowsInstallerSuccess -Output $output -ExitCode 0 -CompletionMarker 'User Phase Complete!' -RequiredOutputMarkers @(
                ('[Npm] ' + [string][char]0x2713 + ' agent-browser@0.38.1')
                $pnpmBootstrapMarker
            )
        } | Should -Not -Throw

        {
            Assert-WindowsInstallerSuccess -Output "Total: 2 | Success: 2 | Failure: 0`nUser Phase Complete!" -ExitCode 0 -CompletionMarker 'User Phase Complete!' -RequiredOutputMarkers @(
                ('[Npm] ' + [string][char]0x2713 + ' agent-browser@0.38.1')
            )
        } | Should -Throw '*required package-manager success marker*'
    }

    It 'rejects a successful phase when the caller supplies no package evidence' {
        $output = 'Total: 1 | Success: 1 | Failure: 0' + [Environment]::NewLine + 'User Phase Complete!'
        { Assert-WindowsInstallerSuccess -Output $output -ExitCode 0 -CompletionMarker 'User Phase Complete!' } |
            Should -Throw '*at least one required package-manager success marker*'
    }

    It 'accepts a clean completed user phase' {
        $wingetSuccessMarker = '[Winget] ' + [string][char]0x2713 + ' package'
        $output = 'Total: 1 | Success: 1 | Failure: 0' + [Environment]::NewLine + $wingetSuccessMarker + [Environment]::NewLine + 'User Phase Complete!'
        { Assert-WindowsInstallerSuccess -Output $output -ExitCode 0 -CompletionMarker 'User Phase Complete!' -RequiredOutputMarkers @($wingetSuccessMarker) } |
            Should -Not -Throw
    }
}
