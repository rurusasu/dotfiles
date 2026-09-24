BeforeAll {
    . (Join-Path $PSScriptRoot "../../ci/Assert-WingetInstallSuccess.ps1")
    . (Join-Path $PSScriptRoot "../../ci/Assert-WindowsInstallerSuccess.ps1")
}

Describe "Assert-WingetInstallSuccess" {
    It "accepts a successful installer summary with a real package install attempt" {
        $output = @"
[Winget] CI_VERIFICATION_INVENTORY: Test.Tool
[Winget] インストール/更新中: Test.Tool
[Winget] ✓ Test.Tool
Total: 1 | Success: 1 | Failure: 0
"@

        { Assert-WingetInstallSuccess -Output $output } | Should -Not -Throw
    }

    It "should require GitHub CLI and Go to appear in and pass the CI verification inventory" {
        $output = @"
[Winget] CI_VERIFICATION_INVENTORY: GitHub.cli|GoLang.Go
[Winget] ✓ GitHub.cli
[Winget] ✓ GoLang.Go
Total: 2 | Success: 2 | Failure: 0
"@

        { Assert-WingetInstallSuccess -Output $output -ExpectedPackageIds @("GitHub.cli", "GoLang.Go") } |
            Should -Not -Throw

        $missingGo = $output -replace '\|GoLang\.Go', '' -replace '\[Winget\] ✓ GoLang\.Go\r?\n', ''
        { Assert-WingetInstallSuccess -Output $missingGo -ExpectedPackageIds @("GitHub.cli", "GoLang.Go") } |
            Should -Throw "*expected Windows E2E packages are missing from the verification inventory: GoLang.Go*"
    }

    It "rejects a successful handler summary when WinGet only reported an unverified no-op" {
        $output = @"
[Winget] CI_VERIFICATION_INVENTORY: Test.Tool
[Winget] インストール/更新中: Test.Tool
[Winget] 変更なし: Test.Tool (winget install は no-op でした)
Total: 1 | Success: 1 | Failure: 0
"@

        { Assert-WingetInstallSuccess -Output $output } | Should -Throw "*missing: Test.Tool*"
    }

    It "accepts a package whose no-op install was verified successfully" {
        $output = @"
[Winget] CI_VERIFICATION_INVENTORY: Test.Tool
[Winget] インストール/更新中: Test.Tool
[Winget] 検証済み: Test.Tool (winget install は no-op でした)
Total: 1 | Success: 1 | Failure: 0
"@

        { Assert-WingetInstallSuccess -Output $output } | Should -Not -Throw
    }

    It "rejects a successful run whose verification inventory omits expected Windows E2E packages" {
        $output = @"
[Winget] CI_VERIFICATION_INVENTORY: Test.Tool
[Winget] ✓ Test.Tool
Total: 1 | Success: 1 | Failure: 0
"@

        { Assert-WingetInstallSuccess -Output $output -ExpectedPackageIds @("Task.Task") } |
            Should -Throw "*expected Windows E2E packages are missing from the verification inventory: Task.Task*"
    }

    It "rejects a verification inventory that contains packages outside the expected Windows E2E scope" {
        $output = @"
[Winget] CI_VERIFICATION_INVENTORY: Test.Tool|Unexpected.Tool
[Winget] ✓ Test.Tool
[Winget] ✓ Unexpected.Tool
Total: 2 | Success: 2 | Failure: 0
"@

        { Assert-WingetInstallSuccess -Output $output -ExpectedPackageIds @("Test.Tool") } |
            Should -Throw "*verification inventory contains packages outside the Windows E2E scope: Unexpected.Tool*"
    }

    It "rejects a nonzero handler failure count even when output has an install attempt" {
        $output = @"
[Winget] CI_VERIFICATION_INVENTORY: Test.Tool
[Winget] インストール/更新中: Test.Tool
Total: 1 | Success: 0 | Failure: 1
"@

        { Assert-WingetInstallSuccess -Output $output } | Should -Throw "*reported 1 failed setup handler*"
    }

    It "includes classified WinGet timeout diagnostics in the CI failure" {
        $output = @"
[Winget] TIMEOUT_DIAGNOSTIC: package=hadolint.hadolint class=installer-cache-contention confidence=high evidence=cached installer file is locked
Total: 1 | Success: 0 | Failure: 1
"@

        { Assert-WingetInstallSuccess -Output $output } | Should -Throw "*installer-cache-contention*cached installer file is locked*"
    }

    It "parses the verification inventory from CRLF installer output" {
        $installerOutput = @(
            "[Winget] CI_VERIFICATION_INVENTORY: Test.Tool"
            "[Winget] ✓ Test.Tool"
            "Total: 1 | Success: 1 | Failure: 0"
        ) -join "`r`n"

        { Assert-WingetInstallSuccess -Output $installerOutput } | Should -Not -Throw
    }

    It "includes timeout diagnostics from CRLF installer output" {
        $installerOutput = @(
            "[Winget] TIMEOUT_DIAGNOSTIC: package=Test.Tool class=installer-cache-contention confidence=high evidence=cached installer file is locked"
            "Total: 1 | Success: 0 | Failure: 1"
        ) -join "`r`n"

        { Assert-WingetInstallSuccess -Output $installerOutput } | Should -Throw "*installer-cache-contention*cached installer file is locked*"
    }

    It "uses manifest-provided expected IDs when the installer did not emit an optional inventory marker" {
        $output = @"
[Winget] ✓ Test.Tool
Total: 1 | Success: 1 | Failure: 0
"@

        { Assert-WingetInstallSuccess -Output $output -ExpectedPackageIds @('Test.Tool') } | Should -Not -Throw
        { Assert-WingetInstallSuccess -Output $output } | Should -Throw "*empty WinGet CI verification inventory*"
    }

    It "rejects package-level failures even if the aggregate summary says success" {
        $output = @"
[Winget] CI_VERIFICATION_INVENTORY: Test.Tool
[Winget] インストール/更新中: Test.Tool
[Winget] ✗ Test.Tool のインストールに失敗しました
Total: 1 | Success: 1 | Failure: 0
"@

        { Assert-WingetInstallSuccess -Output $output } | Should -Throw "*WinGet reported one or more package installation or verification failures*"
    }

    It "rejects a partial package run even when one package succeeded" {
        $output = @"
[Winget] CI_VERIFICATION_INVENTORY: Test.Tool|Other.Tool
[Winget] ✓ Test.Tool
Total: 2 | Success: 1 | Failure: 0
"@

        { Assert-WingetInstallSuccess -Output $output } | Should -Throw "*inconsistent handler counts*"
    }

    It "rejects package IDs reported successful outside the expected inventory" {
        $output = @"
[Winget] CI_VERIFICATION_INVENTORY: Test.Tool
[Winget] ✓ Test.Tool
[Winget] ✓ Extra.Tool
Total: 2 | Success: 2 | Failure: 0
"@

        { Assert-WingetInstallSuccess -Output $output } | Should -Throw "*outside its CI inventory: Extra.Tool*"
    }

    It "rejects an empty WinGet CI inventory" {
        $output = @"
[Winget] CI_VERIFICATION_INVENTORY:
Total: 1 | Success: 1 | Failure: 0
"@

        { Assert-WingetInstallSuccess -Output $output } | Should -Throw "*empty WinGet CI verification inventory*"
    }

    It "rejects successful fallback installation when execution verification was skipped after timeout" {
        $output = @"
[Winget] CI_VERIFICATION_INVENTORY: Test.Tool
[Winget] ✓ Test.Tool (direct fallback 成功、WinGet タイムアウトのため実行検証をスキップ)
Total: 1 | Success: 1 | Failure: 0
"@

        { Assert-WingetInstallSuccess -Output $output } | Should -Throw "*skipped execution verification for a timed-out package*"
    }

    It "rejects missing or unparseable setup summaries" {
        $output = "[Winget] インストール/更新中: Test.Tool"

        { Assert-WingetInstallSuccess -Output $output } | Should -Throw "*did not report a parseable setup summary*"
    }
}

Describe "Assert-WindowsInstallerSuccess summary integrity" {
    It "accepts a complete installer run with reconciled handler counts" {
        $output = @"
Total: 2 | Success: 2 | Failure: 0
User Phase Complete!
[Npm] ✓ package
"@

        {
            Assert-WindowsInstallerSuccess -Output $output -ExitCode 0 -CompletionMarker 'User Phase Complete!' -RequiredOutputMarkers @('[Npm] ✓ package')
        } | Should -Not -Throw
    }

    It "rejects handler summaries whose total does not equal success plus failure" {
        $output = @"
Total: 2 | Success: 1 | Failure: 0
User Phase Complete!
[Npm] ✓ package
"@

        {
            Assert-WindowsInstallerSuccess -Output $output -ExitCode 0 -CompletionMarker 'User Phase Complete!' -RequiredOutputMarkers @('[Npm] ✓ package')
        } | Should -Throw '*inconsistent handler counts*'
    }

    It "rejects missing or repeated setup summaries" {
        $output = "User Phase Complete!`n[Npm] ✓ package"
        {
            Assert-WindowsInstallerSuccess -Output $output -ExitCode 0 -CompletionMarker 'User Phase Complete!' -RequiredOutputMarkers @('[Npm] ✓ package')
        } | Should -Throw '*exactly one parseable setup summary*'

        $output = "Total: 1 | Success: 1 | Failure: 0`nTotal: 1 | Success: 1 | Failure: 0`nUser Phase Complete!`n[Npm] ✓ package"
        {
            Assert-WindowsInstallerSuccess -Output $output -ExitCode 0 -CompletionMarker 'User Phase Complete!' -RequiredOutputMarkers @('[Npm] ✓ package')
        } | Should -Throw '*exactly one parseable setup summary*'
    }
}
