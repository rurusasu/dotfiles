BeforeAll {
    . (Join-Path $PSScriptRoot "../../ci/Assert-WingetInstallSuccess.ps1")
}

Describe "Assert-WingetInstallSuccess" {
    It "accepts a successful installer summary with a real package install attempt" {
        $output = @"
[Winget] インストール/更新中: Test.Tool
Total: 1 | Success: 1 | Failure: 0
"@

        { Assert-WingetInstallSuccess -Output $output } | Should -Not -Throw
    }

    It "rejects a nonzero handler failure count even when output has an install attempt" {
        $output = @"
[Winget] インストール/更新中: Test.Tool
Total: 1 | Success: 0 | Failure: 1
"@

        { Assert-WingetInstallSuccess -Output $output } | Should -Throw "*reported 1 failed setup handler*"
    }

    It "rejects a successful summary when CI never attempted an installation" {
        $output = "Total: 1 | Success: 1 | Failure: 0"

        { Assert-WingetInstallSuccess -Output $output } | Should -Throw "*did not attempt any WinGet package installations*"
    }

    It "rejects package-level failures even if the aggregate summary says success" {
        $output = @"
[Winget] インストール/更新中: Test.Tool
[Winget] ✗ Test.Tool のインストールに失敗しました
Total: 1 | Success: 1 | Failure: 0
"@

        { Assert-WingetInstallSuccess -Output $output } | Should -Throw "*WinGet reported one or more package installation or verification failures*"
    }

    It "rejects missing or unparseable setup summaries" {
        $output = "[Winget] インストール/更新中: Test.Tool"

        { Assert-WingetInstallSuccess -Output $output } | Should -Throw "*did not report a parseable setup summary*"
    }
}
