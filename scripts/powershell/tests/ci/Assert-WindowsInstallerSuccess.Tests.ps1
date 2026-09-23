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

    It 'accepts a clean completed user phase' {
        $output = 'Total: 1 | Success: 1 | Failure: 0' + [Environment]::NewLine + 'User Phase Complete!'
        { Assert-WindowsInstallerSuccess -Output $output -ExitCode 0 -CompletionMarker 'User Phase Complete!' } |
            Should -Not -Throw
    }
}
