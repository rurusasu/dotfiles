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
    foreach ($name in @("Reset-DotfilesTerminalInputMode", "Invoke-CodexCli", "ConvertTo-DcnvimBashSingleQuoted", "dcnvim")) {
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

    function Import-DcnvimProfileFunction {
        foreach ($name in @("ConvertTo-DcnvimBashSingleQuoted", "dcnvim")) {
            Set-Item -Path "Function:\global:$name" -Value $script:functionScriptBlockByName[$name]
        }
    }

    function Import-CodexProfileFunction {
        foreach ($name in @("Reset-DotfilesTerminalInputMode", "Invoke-CodexCli")) {
            Set-Item -Path "Function:\global:$name" -Value $script:functionScriptBlockByName[$name]
        }
    }

    function Get-ArgumentValue {
        param(
            [Parameter(Mandatory)][object[]]$Arguments,
            [Parameter(Mandatory)][string]$Name
        )

        $index = [array]::IndexOf($Arguments, $Name)
        if ($index -lt 0 -or $index + 1 -ge $Arguments.Count) {
            return $null
        }

        return [string]$Arguments[$index + 1]
    }

    function New-DcnvimWorkspace {
        param([Parameter(Mandatory)][string]$Path)

        New-Item -ItemType Directory -Path (Join-Path $Path ".devcontainer") -Force | Out-Null
        return (Resolve-Path -LiteralPath $Path).Path
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

        function global:codex.exe {
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
                "Reset-DotfilesTerminalInputMode",
                "codex.exe"
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
    }

    It 'should alias codex to the compatibility wrapper' {
        $script:profileContent | Should -Match 'Set-Alias\s+-Name\s+codex\s+-Value\s+Invoke-CodexCli'
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

Describe 'PowerShell dcnvim profile function' {
    BeforeEach {
        Import-DcnvimProfileFunction

        $script:devcontainerCalls = [System.Collections.Generic.List[object]]::new()
        $script:devcontainerUpExitCode = 0
        $script:devcontainerExecExitCode = 0
        $script:availableCommands = @{
            devcontainer = $true
            ghq          = $false
            fzf          = $false
        }
        $script:ghqRoot = ""
        $script:ghqList = @()
        $script:fzfSelected = ""
        $script:fzfExitCode = 0
        $script:fzfCallCount = 0
        $script:oldDotfilesRepositoryUrl = $env:DOTFILES_REPOSITORY_URL
        Remove-Item Env:\DOTFILES_REPOSITORY_URL -ErrorAction SilentlyContinue

        function global:Get-Command {
            [CmdletBinding()]
            param(
                [Parameter(Position = 0)]
                [string[]]$Name
            )

            $requestedErrorAction = if ($PSBoundParameters.ContainsKey("ErrorAction")) {
                $PSBoundParameters["ErrorAction"]
            }
            else {
                [System.Management.Automation.ActionPreference]::Continue
            }

            foreach ($commandName in $Name) {
                if ($script:availableCommands.ContainsKey($commandName)) {
                    if ($script:availableCommands[$commandName]) {
                        [PSCustomObject]@{
                            Name        = $commandName
                            CommandType = "Function"
                        }
                    }
                    elseif ($requestedErrorAction -ne [System.Management.Automation.ActionPreference]::SilentlyContinue) {
                        Write-Error "The term '$commandName' is not recognized as a name of a cmdlet, function, script file, or executable program."
                    }
                    continue
                }

                Microsoft.PowerShell.Core\Get-Command @PSBoundParameters
            }
        }

        function global:devcontainer {
            $callArgs = @($args)
            $command = if ($callArgs.Count -gt 0) { [string]$callArgs[0] } else { "" }
            $payload = if ($callArgs.Count -gt 0) { [string]$callArgs[-1] } else { "" }
            $script:devcontainerCalls.Add([PSCustomObject]@{
                    Command = $command
                    Args    = $callArgs
                    Payload = $payload
                }) | Out-Null

            switch ($command) {
                "up" {
                    $global:LASTEXITCODE = $script:devcontainerUpExitCode
                    return
                }
                "exec" {
                    $global:LASTEXITCODE = $script:devcontainerExecExitCode
                    return
                }
                default {
                    $global:LASTEXITCODE = 2
                    return
                }
            }
        }

        function global:ghq {
            switch ($args[0]) {
                "root" {
                    $global:LASTEXITCODE = 0
                    $script:ghqRoot
                    return
                }
                "list" {
                    $global:LASTEXITCODE = 0
                    $script:ghqList
                    return
                }
                default {
                    $global:LASTEXITCODE = 2
                    return
                }
            }
        }

        function global:fzf {
            [CmdletBinding(PositionalBinding = $false)]
            param(
                [Parameter(ValueFromPipeline = $true)]
                [object]$InputObject,

                [string]$Prompt,

                [Parameter(ValueFromRemainingArguments = $true)]
                [object[]]$RemainingArguments
            )

            begin {
                $script:fzfCallCount++
                $script:fzfPrompt = $Prompt
                $script:fzfArgs = @($RemainingArguments)
            }
            process {
                $null = $InputObject
            }
            end {
                if ($script:fzfExitCode -ne 0) {
                    $global:LASTEXITCODE = $script:fzfExitCode
                    return
                }

                $global:LASTEXITCODE = 0
                $script:fzfSelected
            }
        }
    }

    AfterEach {
        foreach ($functionName in @(
                "ConvertTo-DcnvimBashSingleQuoted",
                "dcnvim",
                "devcontainer",
                "ghq",
                "fzf",
                "Get-Command"
            )) {
            Remove-Item "Function:\$functionName" -ErrorAction SilentlyContinue
        }

        if ($null -eq $script:oldDotfilesRepositoryUrl) {
            Remove-Item Env:\DOTFILES_REPOSITORY_URL -ErrorAction SilentlyContinue
        }
        else {
            $env:DOTFILES_REPOSITORY_URL = $script:oldDotfilesRepositoryUrl
        }
    }

    It 'should quote tmux session names for bash payloads' {
        ConvertTo-DcnvimBashSingleQuoted "plain" | Should -Be "'plain'"
        ConvertTo-DcnvimBashSingleQuoted "team's repo" | Should -Be "'team'\''s repo'"
    }

    It 'should run devcontainer up and exec for explicit workspace using absolute paths' {
        $workspace = New-DcnvimWorkspace (Join-Path $TestDrive "repo")

        Push-Location $TestDrive
        try {
            dcnvim -Workspace ".\repo"
        }
        finally {
            Pop-Location
        }

        $script:devcontainerCalls.Count | Should -Be 2
        $up = $script:devcontainerCalls[0]
        $exec = $script:devcontainerCalls[1]

        $up.Command | Should -Be "up"
        Get-ArgumentValue $up.Args "--workspace-folder" | Should -Be $workspace
        Get-ArgumentValue $up.Args "--dotfiles-repository" | Should -Be "https://github.com/rurusasu/dotfiles"
        Get-ArgumentValue $up.Args "--dotfiles-install-command" | Should -Be "bootstrap.sh"

        $exec.Command | Should -Be "exec"
        Get-ArgumentValue $exec.Args "--workspace-folder" | Should -Be $workspace
        $exec.Payload | Should -Match ([regex]::Escape('export PATH="$HOME/.local/bin:$PATH"'))
        $exec.Payload | Should -Match "command -v nvim"
        $exec.Payload | Should -Match "command -v tmux"
        $exec.Payload | Should -Match ([regex]::Escape("tmux new -A -s 'repo' 'nvim .'"))
    }

    It 'should pass custom dotfiles repo URL' {
        $workspace = New-DcnvimWorkspace (Join-Path $TestDrive "repo")
        $env:DOTFILES_REPOSITORY_URL = "https://example.invalid/dotfiles.git"

        dcnvim -Workspace $workspace

        $up = $script:devcontainerCalls[0]
        Get-ArgumentValue $up.Args "--dotfiles-repository" | Should -Be "https://example.invalid/dotfiles.git"
    }

    It 'should use ghq and fzf picker when cwd has no devcontainer config' {
        $script:availableCommands.ghq = $true
        $script:availableCommands.fzf = $true
        $script:ghqRoot = Join-Path $TestDrive "ghq"
        $script:ghqList = @("github.com/foo/bar")
        $script:fzfSelected = "github.com/foo/bar"
        $workspace = New-DcnvimWorkspace (Join-Path $script:ghqRoot "github.com/foo/bar")
        $cwd = Join-Path $TestDrive "cwd"
        New-Item -ItemType Directory -Path $cwd -Force | Out-Null

        Push-Location $cwd
        try {
            dcnvim
        }
        finally {
            Pop-Location
        }

        $script:fzfCallCount | Should -Be 1
        Get-ArgumentValue $script:devcontainerCalls[0].Args "--workspace-folder" | Should -Be $workspace
        $script:devcontainerCalls[1].Payload | Should -Match ([regex]::Escape("tmux new -A -s 'bar' 'nvim .'"))
    }

    It 'should not invoke fzf when fzf is unavailable' {
        $script:availableCommands.ghq = $true
        $script:availableCommands.fzf = $false
        $cwd = Join-Path $TestDrive "cwd"
        New-Item -ItemType Directory -Path $cwd -Force | Out-Null

        Push-Location $cwd
        try {
            { dcnvim -ErrorAction Stop } | Should -Throw -ExpectedMessage "*dcnvim: no .devcontainer/ or .devcontainer.json under*"
        }
        finally {
            Pop-Location
        }

        $script:fzfCallCount | Should -Be 0
        $script:devcontainerCalls.Count | Should -Be 0
    }

    It 'should fail before devcontainer up when workspace lacks devcontainer config' {
        $workspace = Join-Path $TestDrive "no-config-repo"
        New-Item -ItemType Directory -Path $workspace -Force | Out-Null

        { dcnvim -Workspace $workspace -ErrorAction Stop } |
            Should -Throw -ExpectedMessage "*dcnvim: no .devcontainer/ or .devcontainer.json under*"

        $script:devcontainerCalls.Count | Should -Be 0
    }

    It 'should fail before devcontainer exec when devcontainer up fails' {
        $workspace = New-DcnvimWorkspace (Join-Path $TestDrive "repo")
        $script:devcontainerUpExitCode = 42

        { dcnvim -Workspace $workspace -ErrorAction Stop } |
            Should -Throw -ExpectedMessage "*dcnvim: devcontainer up failed (exit 42)*"

        $script:devcontainerCalls.Count | Should -Be 1
        $script:devcontainerCalls[0].Command | Should -Be "up"
    }

    It 'should report missing devcontainer CLI before invoking it' {
        $workspace = New-DcnvimWorkspace (Join-Path $TestDrive "repo")
        $script:availableCommands.devcontainer = $false

        { dcnvim -Workspace $workspace -ErrorAction Stop } |
            Should -Throw -ExpectedMessage "*dcnvim: devcontainer CLI not found*"

        $script:devcontainerCalls.Count | Should -Be 0
    }

    It 'should quote single quotes in generated tmux session names' {
        $workspace = New-DcnvimWorkspace (Join-Path $TestDrive "team's repo")

        dcnvim -Workspace $workspace

        $script:devcontainerCalls[1].Payload |
            Should -Match ([regex]::Escape("tmux new -A -s 'team'\''s repo' 'nvim .'"))
    }
}
