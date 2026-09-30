BeforeAll {
    . (Join-Path $PSScriptRoot '../../ci/Assert-WezTermInstallEvidence.ps1')
}

Describe 'Assert-WezTermInstallEvidence' {
    BeforeEach {
        $script:evidence = @'
[Winget] PACKAGE_PHASE: package=wez.wezterm phase=install status=started timeoutSeconds=900
[Winget] PACKAGE_PHASE: package=wez.wezterm phase=install status=completed elapsedMs=1000 exitCode=0 exitCodeHex=00000000
[Winget] PACKAGE_PHASE: package=wez.wezterm phase=path status=started
[Winget] PACKAGE_PHASE: package=wez.wezterm phase=path status=completed elapsedMs=10
[Winget] PACKAGE_PHASE: command=wezterm phase=verify status=started executable=wezterm timeoutSeconds=900
[Winget] PACKAGE_PHASE: command=wezterm phase=verify status=completed elapsedMs=100 exitCode=0
'@
    }

    It 'should accept actual install PATH and version evidence' {
        {
            Assert-WezTermInstallEvidence -Output $script:evidence -PackageId 'wez.wezterm' `
                -VersionOutput 'wezterm 20240203-110809-5046fc22' -VersionExitCode 0
        } | Should -Not -Throw
    }

    It 'should reject missing <Phase> completion evidence' -TestCases @(
        @{ Phase = 'install' }
        @{ Phase = 'path' }
        @{ Phase = 'verify' }
    ) {
        param($Phase)
        $incomplete = ($script:evidence -split "`n" | Where-Object { $_ -notmatch "phase=$Phase status=completed" }) -join "`n"
        {
            Assert-WezTermInstallEvidence -Output $incomplete -PackageId 'wez.wezterm' `
                -VersionOutput 'wezterm 20240203-110809-5046fc22' -VersionExitCode 0
        } | Should -Throw '*phase evidence*'
    }

    It 'should reject nonzero install or verification exits even with valid version output' -TestCases @(
        @{ Phase = 'install' }
        @{ Phase = 'verify' }
    ) {
        param($Phase)
        $failed = $script:evidence -replace "(phase=$Phase status=completed elapsedMs=\d+ exitCode=)0", '${1}124'
        {
            Assert-WezTermInstallEvidence -Output $failed -PackageId 'wez.wezterm' `
                -VersionOutput 'wezterm 20240203-110809-5046fc22' -VersionExitCode 0
        } | Should -Throw '*phase evidence*'
    }

    It 'should reject a version result from another command or a failed child process' -TestCases @(
        @{ VersionOutput = 'another-tool 1.2.3'; ExitCode = 0 }
        @{ VersionOutput = 'wezterm 20240203-110809-5046fc22'; ExitCode = 127 }
    ) {
        param($VersionOutput, $ExitCode)
        {
            Assert-WezTermInstallEvidence -Output $script:evidence -PackageId 'wez.wezterm' `
                -VersionOutput $VersionOutput -VersionExitCode $ExitCode
        } | Should -Throw '*fresh PATH command*'
    }

    It 'should reject version and PATH evidence that preceded installation' {
        $lines = @($script:evidence -split "`n")
        $reordered = (@($lines[2..5]) + @($lines[0..1])) -join "`n"
        {
            Assert-WezTermInstallEvidence -Output $reordered -PackageId 'wez.wezterm' `
                -VersionOutput 'wezterm 20240203-110809-5046fc22' -VersionExitCode 0
        } | Should -Throw '*phase evidence*'
    }
}
