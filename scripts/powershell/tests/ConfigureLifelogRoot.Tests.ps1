#Requires -Module Pester

BeforeAll {
    $script:repoRoot = Resolve-Path (Join-Path $PSScriptRoot "../../..")
    $script:scriptPath = Join-Path $script:repoRoot "scripts/powershell/configure-lifelog-root.ps1"
}

Describe 'configure-lifelog-root.ps1' {
    It 'exists as an explicit setup entrypoint' {
        Test-Path -LiteralPath $script:scriptPath -PathType Leaf | Should -BeTrue
    }

    It 'requires -Path and does not contain a default lifelog path' {
        $content = Get-Content -LiteralPath $script:scriptPath -Raw

        $content | Should -Match '\[Parameter\(Mandatory\s*=\s*\$true\)\]\s*\[string\]\$Path' -Because 'the caller must choose the lifelog root'
        $content | Should -Not -Match 'D:\\\\lifelog|D:/lifelog|\.openclaw\\workspace' -Because 'the script must not bake in a candidate root'
        $content | Should -Not -Match 'Get-ChildItem.*lifelog|Resolve-Path.*lifelog' -Because 'the script must not discover lifelog by scanning the filesystem'
    }

    It 'fails when the explicit path is not a lifelog root' {
        $root = Join-Path $TestDrive "not-lifelog"
        New-Item -ItemType Directory -Path $root -Force | Out-Null

        $result = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $script:scriptPath `
            -Path $root `
            -EnvironmentTarget Process `
            -SkipChezmoiApply 2>&1

        $LASTEXITCODE | Should -Not -Be 0
        ($result | Out-String) | Should -Match 'AGENTS\.md'
    }

    It 'validates the explicit path with git and runs chezmoi init/apply with LIFELOG_ROOT set' {
        $root = Join-Path $TestDrive "explicit-root"
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $root ".git") -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $root "AGENTS.md") -Value "# lifelog" -Encoding UTF8

        $log = Join-Path $TestDrive "calls.log"
        $gitStub = Join-Path $TestDrive "git-stub.cmd"
        $chezmoiStub = Join-Path $TestDrive "chezmoi-stub.cmd"

        Set-Content -LiteralPath $gitStub -Encoding UTF8 -Value @'
@echo off
>> "%CONFIGURE_LIFELOG_TEST_LOG%" echo git %*
if "%~3"=="rev-parse" if "%~4"=="--show-toplevel" (
  echo %CONFIGURE_LIFELOG_TEST_ROOT%
  exit /b 0
)
if "%~3"=="rev-parse" if "%~4"=="--git-dir" (
  echo %CONFIGURE_LIFELOG_TEST_ROOT%\.git
  exit /b 0
)
if "%~3"=="remote" if "%~4"=="get-url" if "%~5"=="origin" (
  echo https://github.com/rurusasu/lifelog.git
  exit /b 0
)
exit /b 1
'@

        Set-Content -LiteralPath $chezmoiStub -Encoding UTF8 -Value @'
@echo off
>> "%CONFIGURE_LIFELOG_TEST_LOG%" echo chezmoi %* LIFELOG_ROOT=%LIFELOG_ROOT%
exit /b 0
'@

        $env:CONFIGURE_LIFELOG_TEST_LOG = $log
        $env:CONFIGURE_LIFELOG_TEST_ROOT = [System.IO.Path]::GetFullPath($root).TrimEnd("\")
        try {
            & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $script:scriptPath `
                -Path $root `
                -GitCommand $gitStub `
                -ChezmoiCommand $chezmoiStub `
                -ChezmoiSource (Join-Path $script:repoRoot "chezmoi") `
                -EnvironmentTarget Process | Out-Null

            $LASTEXITCODE | Should -Be 0
            $calls = Get-Content -LiteralPath $log
            ($calls -join "`n") | Should -Match 'git .*rev-parse --show-toplevel'
            ($calls -join "`n") | Should -Match 'git .*rev-parse --git-dir'
            ($calls -join "`n") | Should -Match 'git .*remote get-url origin'
            ($calls -join "`n") | Should -Match 'chezmoi .*init .*--source'
            ($calls -join "`n") | Should -Match ('--promptString LIFELOG_ROOT=' + [regex]::Escape($env:CONFIGURE_LIFELOG_TEST_ROOT))
            ($calls -join "`n") | Should -Match 'chezmoi .*apply .*--source'
            ($calls -join "`n") | Should -Match ('LIFELOG_ROOT=' + [regex]::Escape($env:CONFIGURE_LIFELOG_TEST_ROOT))
        }
        finally {
            Remove-Item Env:\CONFIGURE_LIFELOG_TEST_LOG -ErrorAction SilentlyContinue
            Remove-Item Env:\CONFIGURE_LIFELOG_TEST_ROOT -ErrorAction SilentlyContinue
        }
    }
}
