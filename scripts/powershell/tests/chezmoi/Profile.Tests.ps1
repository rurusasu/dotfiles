#Requires -Module Pester

BeforeAll {
    $script:repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../../../..")).Path
    $script:profilePath = Join-Path $script:repoRoot "chezmoi/shells/Microsoft.PowerShell_profile.ps1"
    $script:profileContent = Get-Content -LiteralPath $script:profilePath -Raw

    $tokens = $null
    $parseErrors = $null
    $profileAst = [System.Management.Automation.Language.Parser]::ParseFile(
        $script:profilePath,
        [ref]$tokens,
        [ref]$parseErrors
    )
    if ($parseErrors) {
        throw "Failed to parse Microsoft.PowerShell_profile.ps1: $($parseErrors -join '; ')"
    }

    $script:functionScriptBlockByName = @{}
    foreach ($name in @("Merge-DotfilesPathEntries", "Reset-DotfilesTerminalInputMode", "Resolve-DotfilesCodexExecutable", "Invoke-CodexCli", "Import-MsvcDevEnvironment", "cargo-msvc", "nvim-msvc")) {
        $functionAst = $profileAst.Find(
            {
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq $name
            },
            $true
        )
        if (-not $functionAst) {
            throw "Function not found in Microsoft.PowerShell_profile.ps1: $name"
        }
        $script:functionScriptBlockByName[$name] = $functionAst.Body.GetScriptBlock()
    }

    function Import-CodexProfileFunction {
        foreach ($name in @("Reset-DotfilesTerminalInputMode", "Resolve-DotfilesCodexExecutable", "Invoke-CodexCli")) {
            Set-Item -Path "Function:\global:$name" -Value $script:functionScriptBlockByName[$name]
        }
    }

    function Import-PathProfileFunction {
        Set-Item -Path "Function:\global:Merge-DotfilesPathEntries" -Value $script:functionScriptBlockByName["Merge-DotfilesPathEntries"]
    }

    function Import-MsvcProfileFunction {
        foreach ($name in @("Import-MsvcDevEnvironment", "cargo-msvc", "nvim-msvc")) {
            Set-Item -Path "Function:\global:$name" -Value $script:functionScriptBlockByName[$name]
        }
    }
}

Describe 'PowerShell MSVC dev environment helpers' {
    BeforeEach {
        Import-MsvcProfileFunction

        $script:oldProgramFilesX86 = ${env:ProgramFiles(x86)}
        $script:oldPath = $env:PATH
        $script:oldLibExists = Test-Path Env:\LIB
        $script:oldLib = $env:LIB
        $script:oldIncludeExists = Test-Path Env:\INCLUDE
        $script:oldInclude = $env:INCLUDE
        $script:oldVscmdExists = Test-Path Env:\VSCMD_VER
        $script:oldVscmd = $env:VSCMD_VER
        $script:cmdArgs = $null
        $script:cargoArgs = $null
        $script:nvimArgs = $null

        ${env:ProgramFiles(x86)} = $TestDrive
        $toolsDir = Join-Path $TestDrive "Microsoft Visual Studio\2022\BuildTools\Common7\Tools"
        New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $toolsDir "VsDevCmd.bat") -Force | Out-Null

        function global:cmd.exe {
            $script:cmdArgs = [string[]]$args
            $global:LASTEXITCODE = 0
            @(
                "PATH=C:\msvc\bin;C:\Windows\System32",
                "LIB=C:\msvc\lib;C:\sdk\lib",
                "INCLUDE=C:\msvc\include;C:\sdk\include",
                "VSCMD_VER=17.14.35",
                "VALUE_WITH_EQUALS=left=right"
            )
        }

        function global:cargo {
            $script:cargoArgs = [string[]]$args
            $global:LASTEXITCODE = 11
        }

        function global:nvim {
            $script:nvimArgs = [string[]]$args
            $global:LASTEXITCODE = 12
        }
    }

    AfterEach {
        foreach ($functionName in @(
                "Import-MsvcDevEnvironment",
                "cargo-msvc",
                "nvim-msvc",
                "cmd.exe",
                "cargo",
                "nvim"
            )) {
            Remove-Item "Function:\$functionName" -ErrorAction SilentlyContinue
        }

        ${env:ProgramFiles(x86)} = $script:oldProgramFilesX86
        $env:PATH = $script:oldPath

        if ($script:oldLibExists) { $env:LIB = $script:oldLib } else { Remove-Item Env:\LIB -ErrorAction SilentlyContinue }
        if ($script:oldIncludeExists) { $env:INCLUDE = $script:oldInclude } else { Remove-Item Env:\INCLUDE -ErrorAction SilentlyContinue }
        if ($script:oldVscmdExists) { $env:VSCMD_VER = $script:oldVscmd } else { Remove-Item Env:\VSCMD_VER -ErrorAction SilentlyContinue }
        Remove-Item Env:\VALUE_WITH_EQUALS -ErrorAction SilentlyContinue
    }

    It 'should import MSVC developer environment variables into the current PowerShell process' {
        Import-MsvcDevEnvironment

        $script:cmdArgs | Should -Contain "/d"
        $script:cmdArgs | Should -Contain "/v:on"
        ($script:cmdArgs -join " ") | Should -Match "VsDevCmd\.bat"
        ($script:cmdArgs -join " ") | Should -Match "-arch=x64"
        $env:PATH | Should -Be "C:\msvc\bin;C:\Windows\System32"
        $env:LIB | Should -Be "C:\msvc\lib;C:\sdk\lib"
        $env:INCLUDE | Should -Be "C:\msvc\include;C:\sdk\include"
        $env:VSCMD_VER | Should -Be "17.14.35"
        $env:VALUE_WITH_EQUALS | Should -Be "left=right"
    }

    It 'should run cargo and nvim through the MSVC developer environment wrappers' {
        cargo-msvc test --locked
        $script:cargoArgs | Should -Be @("test", "--locked")
        $global:LASTEXITCODE | Should -Be 11

        nvim-msvc .
        $script:nvimArgs | Should -Be @(".")
        $global:LASTEXITCODE | Should -Be 12
    }

    It 'should expose an msvcdev alias for loading the current shell' {
        $script:profileContent | Should -Match 'Set-Alias\s+-Name\s+msvcdev\s+-Value\s+Import-MsvcDevEnvironment'
    }
}

Describe 'PowerShell codex profile wrapper' {
    BeforeEach {
        Import-CodexProfileFunction

        $script:codexArgs = $null
        $script:termDuringCodex = $null
        $script:keyboardEnhancementDuringCodex = $null
        $script:resetCalls = 0
        $script:oldTermExists = Test-Path Env:\TERM
        $script:oldTerm = $env:TERM
        $script:oldKeyboardEnhancementExists = Test-Path Env:\CODEX_TUI_DISABLE_KEYBOARD_ENHANCEMENT
        $script:oldKeyboardEnhancement = $env:CODEX_TUI_DISABLE_KEYBOARD_ENHANCEMENT
        $script:oldLocalAppDataExists = Test-Path Env:\LOCALAPPDATA
        $script:oldLocalAppData = $env:LOCALAPPDATA
        $env:LOCALAPPDATA = Join-Path $TestDrive 'LocalAppDataWithoutCodexPackage'

        function global:codex.cmd {
            $script:codexArgs = [string[]]$args
            $script:termDuringCodex = $env:TERM
            $script:keyboardEnhancementDuringCodex = $env:CODEX_TUI_DISABLE_KEYBOARD_ENHANCEMENT
            $global:LASTEXITCODE = 7
        }

        function global:Reset-DotfilesTerminalInputMode {
            $script:resetCalls++
        }
    }

    AfterEach {
        foreach ($functionName in @(
                "Invoke-CodexCli",
                "Resolve-DotfilesCodexExecutable",
                "Reset-DotfilesTerminalInputMode",
                "codex.cmd"
            )) {
            Remove-Item "Function:\$functionName" -ErrorAction SilentlyContinue
        }

        if ($script:oldTermExists) {
            $env:TERM = $script:oldTerm
        }
        else {
            Remove-Item Env:\TERM -ErrorAction SilentlyContinue
        }

        if ($script:oldKeyboardEnhancementExists) {
            $env:CODEX_TUI_DISABLE_KEYBOARD_ENHANCEMENT = $script:oldKeyboardEnhancement
        }
        else {
            Remove-Item Env:\CODEX_TUI_DISABLE_KEYBOARD_ENHANCEMENT -ErrorAction SilentlyContinue
        }

        if ($script:oldLocalAppDataExists) {
            $env:LOCALAPPDATA = $script:oldLocalAppData
        }
        else {
            Remove-Item Env:\LOCALAPPDATA -ErrorAction SilentlyContinue
        }
    }

    It 'should alias codex to the compatibility wrapper' {
        $script:profileContent | Should -Match 'Set-Alias\s+-Name\s+codex\s+-Value\s+Invoke-CodexCli'
    }

    It 'should load missing Codex secrets before launching the direct TUI' {
        $codexBlock = [regex]::Match(
            $script:profileContent,
            '(?s)function Invoke-CodexCli \{.*?\r?\n\}\r?\n\r?\nSet-Alias'
        ).Value

        $codexBlock | Should -Match 'DOTFILES_FORCE_SECRET_LOAD'
        $codexBlock | Should -Match '\.config\\shell\\secret\.ps1'
        $codexBlock | Should -Not -Match 'opCommand'
        $codexBlock | Should -Not -Match 'opArgs'
    }

    It 'should resolve the npm-installed codex command' {
        $oldAppData = $env:APPDATA
        try {
            $env:APPDATA = Join-Path $TestDrive 'AppData'
            $npmDir = Join-Path $env:APPDATA 'npm'
            $npmCommand = Join-Path $npmDir 'codex.cmd'
            New-Item -ItemType Directory -Path $npmDir -Force | Out-Null
            Set-Content -LiteralPath $npmCommand -Encoding ascii -Value '@echo off'

            Mock Get-Command {
                [pscustomobject]@{ Source = $npmCommand; Path = $npmCommand; Name = 'codex.cmd' }
            } -ParameterFilter { $Name -eq 'codex.cmd' }

            Resolve-DotfilesCodexExecutable | Should -Be $npmCommand
        }
        finally {
            if ($oldAppData) {
                $env:APPDATA = $oldAppData
            }
            else {
                Remove-Item Env:\APPDATA -ErrorAction SilentlyContinue
            }
        }
    }

    It 'should run codex.exe with conservative terminal input settings and restore the environment' {
        $env:TERM = "wezterm"
        Remove-Item Env:\CODEX_TUI_DISABLE_KEYBOARD_ENHANCEMENT -ErrorAction SilentlyContinue

        Invoke-CodexCli resume --last

        $script:codexArgs | Should -Be @("resume", "--last")
        $script:termDuringCodex | Should -Be "xterm-256color"
        $script:keyboardEnhancementDuringCodex | Should -Be "1"
        $env:TERM | Should -Be "wezterm"
        Test-Path Env:\CODEX_TUI_DISABLE_KEYBOARD_ENHANCEMENT | Should -BeFalse
        $script:resetCalls | Should -Be 2
        $global:LASTEXITCODE | Should -Be 7
    }

    It 'should forward short Codex flags without PowerShell common parameter binding' {
        $env:TERM = "wezterm"

        Invoke-CodexCli -V

        $script:codexArgs | Should -Be @("-V")
        $script:termDuringCodex | Should -Be "xterm-256color"
        $env:TERM | Should -Be "wezterm"
    }
}

Describe 'PowerShell VS Code lightweight profile path' {
    It 'should expose CLI wrappers before the VS Code lightweight return while merging PATH entries' {
        $returnIndex = $script:profileContent.IndexOf('if ($env:VSCODE_PID -or $env:VSCODE_INJECTION) { return }')
        ($returnIndex -ge 0) | Should -BeTrue

        $pathFunctionIndex = $script:profileContent.IndexOf('function Merge-DotfilesPathEntries')
        $pathInvocationIndex = $script:profileContent.IndexOf('$env:PATH = Merge-DotfilesPathEntries')
        $codexAliasIndex = $script:profileContent.IndexOf('Set-Alias -Name codex -Value Invoke-CodexCli')

        ($pathFunctionIndex -ge 0) | Should -BeTrue
        ($pathInvocationIndex -ge 0) | Should -BeTrue
        ($codexAliasIndex -ge 0) | Should -BeTrue

        $codexAliasIndex | Should -BeLessThan $returnIndex
    }
}

Describe 'PowerShell PATH repair' {
    BeforeEach {
        Import-PathProfileFunction
    }

    It 'should preserve inherited entries and append missing Machine and User entries once' {
        Merge-DotfilesPathEntries `
            -InheritedPath 'C:\inherited;C:\Shared;C:\Inherited' `
            -MachinePath 'C:\Machine;C:\Shared' `
            -UserPath 'C:\User;C:\machine' |
            Should -Be 'C:\inherited;C:\Shared;C:\Machine;C:\User'
    }
}

