# PowerShell profile managed by chezmoi

# Codex integrated shells can start with a trimmed Windows environment. Repair the
# minimum variables that Windows DNS, chezmoi, winget, and developer tools expect.
$_machine_system_root = [Environment]::GetEnvironmentVariable("SystemRoot", "Machine")
if (-not $_machine_system_root -or $_machine_system_root -like "*%*") { $_machine_system_root = "C:\WINDOWS" }
if (-not $env:SystemRoot -or $env:SystemRoot -like "*%*") { $env:SystemRoot = $_machine_system_root }
if (-not $env:WINDIR -or $env:WINDIR -like "*%*") { $env:WINDIR = $_machine_system_root }
if (-not $env:ComSpec -or $env:ComSpec -like "*%*") { $env:ComSpec = Join-Path $_machine_system_root "System32\cmd.exe" }
if (-not $env:USERPROFILE) { $env:USERPROFILE = [Environment]::GetFolderPath("UserProfile") }
if (-not $env:HOME) { $env:HOME = $env:USERPROFILE }
if (-not $env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME = Join-Path $env:HOME ".config" }
if (-not $env:XDG_CACHE_HOME) { $env:XDG_CACHE_HOME = Join-Path $env:HOME ".cache" }
if (-not $env:XDG_DATA_HOME) { $env:XDG_DATA_HOME = Join-Path $env:HOME ".local\share" }
if (-not $env:DIRENV_CONFIG) { $env:DIRENV_CONFIG = Join-Path $env:XDG_CONFIG_HOME "direnv" }
if (-not $env:LOCALAPPDATA) { $env:LOCALAPPDATA = [Environment]::GetFolderPath("LocalApplicationData") }
if (-not $env:APPDATA) { $env:APPDATA = [Environment]::GetFolderPath("ApplicationData") }
if (-not $env:TEMP -or $env:TEMP -eq $env:USERPROFILE) { $env:TEMP = Join-Path $env:LOCALAPPDATA "Temp" }
if (-not $env:TMP) { $env:TMP = $env:TEMP }
if (-not $env:TERM -or $env:TERM -eq "dumb") { $env:TERM = "xterm-256color" }

function Merge-DotfilesPathEntries {
    param(
        [AllowNull()][string]$InheritedPath,
        [AllowNull()][string]$MachinePath,
        [AllowNull()][string]$UserPath
    )

    $pathEntries = [System.Collections.Generic.List[string]]::new()
    $seenPathEntries = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($pathValue in @($InheritedPath, $MachinePath, $UserPath)) {
        if ([string]::IsNullOrWhiteSpace($pathValue)) { continue }

        foreach ($pathEntry in ($pathValue -split ";")) {
            $normalizedPathEntry = $pathEntry.Trim()
            if (-not $normalizedPathEntry -or -not $seenPathEntries.Add($normalizedPathEntry)) { continue }
            [void]$pathEntries.Add($normalizedPathEntry)
        }
    }

    return ($pathEntries -join ";")
}

$_machine_path = [Environment]::GetEnvironmentVariable("PATH", "Machine")
$_user_path = [Environment]::GetEnvironmentVariable("PATH", "User")
$env:PATH = Merge-DotfilesPathEntries -InheritedPath $env:PATH -MachinePath $_machine_path -UserPath $_user_path
Remove-Variable _machine_path, _user_path -ErrorAction SilentlyContinue

# Tell snacks.nvim to use WezTerm's Kitty graphics protocol for image preview.
$env:SNACKS_WEZTERM = "true"

function Reset-DotfilesTerminalInputMode {
    $escape = [char]27
    $host.UI.Write(
        "$escape[?1000l$escape[?1002l$escape[?1003l$escape[?1004l" +
        "$escape[?1005l$escape[?1006l$escape[?1015l$escape[?2004l" +
        "$escape[<u$escape[>4;0m"
    )
}

function Resolve-DotfilesCodexExecutable {
    foreach ($commandName in @("codex.exe", "codex.cmd")) {
        $codexCommand = Get-Command $commandName -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($codexCommand) {
            if ($codexCommand.Source) {
                return $codexCommand.Source
            }

            if ($codexCommand.Path) {
                return $codexCommand.Path
            }

            return $codexCommand.Name
        }
    }

    throw "Codex CLI was not found. Enable the CLI provided by the ChatGPT app."
}

function Invoke-CodexCli {
    $codexArgs = [string[]]$args
    $hadTerm = Test-Path Env:\TERM
    $previousTerm = $env:TERM
    $hadKeyboardEnhancement = Test-Path Env:\CODEX_TUI_DISABLE_KEYBOARD_ENHANCEMENT
    $previousKeyboardEnhancement = $env:CODEX_TUI_DISABLE_KEYBOARD_ENHANCEMENT
    $hadForceSecretLoad = Test-Path Env:\DOTFILES_FORCE_SECRET_LOAD
    $previousForceSecretLoad = $env:DOTFILES_FORCE_SECRET_LOAD

    try {
        $env:TERM = "xterm-256color"
        $env:CODEX_TUI_DISABLE_KEYBOARD_ENHANCEMENT = "1"
        Reset-DotfilesTerminalInputMode

        $codexExecutable = Resolve-DotfilesCodexExecutable
        $secretLoader = if ($HOME) { Join-Path $HOME ".config\shell\secret.ps1" } else { $null }
        if (
            (-not $env:GITHUB_PAT_TOKEN -or -not $env:GITHUB_WORK_TOKEN) -and
            $secretLoader -and
            (Test-Path -LiteralPath $secretLoader -PathType Leaf)
        ) {
            $env:DOTFILES_FORCE_SECRET_LOAD = "1"
            . $secretLoader
        }

        & $codexExecutable @codexArgs
    }
    finally {
        $codexExitCode = $global:LASTEXITCODE

        if ($hadTerm) {
            $env:TERM = $previousTerm
        }
        else {
            Remove-Item Env:\TERM -ErrorAction SilentlyContinue
        }

        if ($hadKeyboardEnhancement) {
            $env:CODEX_TUI_DISABLE_KEYBOARD_ENHANCEMENT = $previousKeyboardEnhancement
        }
        else {
            Remove-Item Env:\CODEX_TUI_DISABLE_KEYBOARD_ENHANCEMENT -ErrorAction SilentlyContinue
        }

        if ($hadForceSecretLoad) {
            $env:DOTFILES_FORCE_SECRET_LOAD = $previousForceSecretLoad
        }
        else {
            Remove-Item Env:\DOTFILES_FORCE_SECRET_LOAD -ErrorAction SilentlyContinue
        }

        Reset-DotfilesTerminalInputMode
        $global:LASTEXITCODE = $codexExitCode
    }
}

Set-Alias -Name codex -Value Invoke-CodexCli -Scope Global

# VS Code sets VSCODE_PID in integrated terminals as well as extension consoles.
# Keep PATH repair and CLI wrappers above this return, then skip heavy init
# (starship/zoxide/PSReadLine) to avoid extension-console startup timeouts.
if ($env:VSCODE_PID -or $env:VSCODE_INJECTION) { return }

function Import-MsvcDevEnvironment {
    [CmdletBinding()]
    param(
        [ValidateSet("x64", "x86", "arm64")]
        [string]$Arch = "x64",

        [ValidateSet("x64", "x86")]
        [string]$HostArch = "x64"
    )

    $programFilesX86 = ${env:ProgramFiles(x86)}
    if (-not $programFilesX86) {
        $programFilesX86 = Join-Path $env:SystemDrive "Program Files (x86)"
    }

    $installPath = $null
    $vswhere = Join-Path $programFilesX86 "Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path -LiteralPath $vswhere -PathType Leaf) {
        $installPath = & $vswhere `
            -all `
            -products * `
            -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
            -property installationPath 2>$null |
            Select-Object -First 1
    }

    if (-not $installPath) {
        $candidate = Join-Path $programFilesX86 "Microsoft Visual Studio\2022\BuildTools"
        if (Test-Path -LiteralPath (Join-Path $candidate "Common7\Tools\VsDevCmd.bat") -PathType Leaf) {
            $installPath = $candidate
        }
    }

    if (-not $installPath) {
        throw "MSVC Build Tools not found. Install Microsoft.VisualStudio.2022.BuildTools with the VCTools workload."
    }

    $vsDevCmd = Join-Path $installPath "Common7\Tools\VsDevCmd.bat"
    if (-not (Test-Path -LiteralPath $vsDevCmd -PathType Leaf)) {
        throw "VsDevCmd.bat not found: $vsDevCmd"
    }

    $cmdLine = "call `"$vsDevCmd`" -arch=$Arch -host_arch=$HostArch >nul && set"
    $envLines = & cmd.exe /d /v:on /c $cmdLine
    if ($LASTEXITCODE -ne 0) {
        throw "VsDevCmd.bat failed with exit code $LASTEXITCODE"
    }

    foreach ($line in $envLines) {
        $text = [string]$line
        $separatorIndex = $text.IndexOf("=")
        if ($separatorIndex -le 0) { continue }

        $name = $text.Substring(0, $separatorIndex)
        $value = $text.Substring($separatorIndex + 1)
        Set-Item -Path "Env:\$name" -Value $value
    }
}

Set-Alias -Name msvcdev -Value Import-MsvcDevEnvironment -Scope Global

function cargo-msvc {
    $cargoArgs = [string[]]$args
    Import-MsvcDevEnvironment
    & cargo @cargoArgs
}

function nvim-msvc {
    $nvimArgs = [string[]]$args
    Import-MsvcDevEnvironment
    & nvim @nvimArgs
}

# Aliases
if (Get-Command rg -ErrorAction SilentlyContinue) {
    Set-Alias -Name grep -Value rg -Scope Global
}
if (Get-Command fd -ErrorAction SilentlyContinue) {
    Set-Alias -Name find -Value fd -Scope Global
}
if (Get-Command eza -ErrorAction SilentlyContinue) {
    Remove-Item Alias:ls -Force -ErrorAction SilentlyContinue
    function Test-DotfilesNonFileSystemPath {
        param([object[]]$Arguments)

        foreach ($argument in $Arguments) {
            if ($argument -isnot [string] -or $argument.StartsWith("-")) { continue }
            if ($argument -notmatch '^[^\\/:\s]+:') { continue }

            try {
                $resolvedPaths = $ExecutionContext.SessionState.Path.GetResolvedPSPathFromPSPath($argument)
                foreach ($resolvedPath in $resolvedPaths) {
                    if ($resolvedPath.Provider.Name -ne "FileSystem") { return $true }
                }
            }
            catch {
                return $true
            }
        }
        return $false
    }

    function Invoke-DotfilesEza {
        param(
            [string[]]$EzaArgs,
            [object[]]$RemainingArgs
        )

        if (Test-DotfilesNonFileSystemPath -Arguments $RemainingArgs) {
            Get-ChildItem @RemainingArgs
            return
        }

        eza @EzaArgs @RemainingArgs
    }

    function ls { Invoke-DotfilesEza -EzaArgs @("-lhaT", "--level=1", "--icons=auto", "--hyperlink", "-F", "--group-directories-first", "--color=auto") -RemainingArgs $args }
    function ll { Invoke-DotfilesEza -EzaArgs @("-lhaT", "--level=2", "--icons=auto", "--hyperlink", "-F", "--group-directories-first", "--color=auto") -RemainingArgs $args }
    function la { Invoke-DotfilesEza -EzaArgs @("-lhaT", "--level=2", "--icons=auto", "--hyperlink", "-F", "--group-directories-first", "--color=auto") -RemainingArgs $args }
    function l { Invoke-DotfilesEza -EzaArgs @("-lhaT", "--level=2", "--icons=auto", "--hyperlink", "-F", "--group-directories-first", "--color=auto") -RemainingArgs $args }
}

# OSC 7 support (advises terminal of current working directory)
function Write-Osc7CurrentDirectory {
    $current_location = $executionContext.SessionState.Path.CurrentLocation
    if ($current_location.Provider.Name -ne "FileSystem") { return }
    $ansi_escape = [char]27
    $provider_path = $current_location.ProviderPath -replace "\\", "/"
    $osc7 = "$ansi_escape]7;file://${env:COMPUTERNAME}/${provider_path}$ansi_escape\\"
    $host.UI.Write($osc7)
}

# Disable Oh My Posh if present (starship takes over prompt)
if ($env:POSH_THEME) { Remove-Item Env:\POSH_THEME -ErrorAction SilentlyContinue }

# starship prompt
if (Get-Command starship -ErrorAction SilentlyContinue) {
    function Invoke-Starship-PreCommand {
        Write-Osc7CurrentDirectory
    }
    Invoke-Expression (& starship init powershell)
}

# zoxide (must init AFTER starship so the prompt hook survives)
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression (& zoxide init powershell | Out-String)
}
else {
    # Fallback: emit OSC 7 on each prompt without changing default prompt text
    if (-not $script:DotfilesOriginalPrompt -and (Test-Path Function:\prompt)) {
        $script:DotfilesOriginalPrompt = $Function:prompt
    }
    function global:prompt {
        Write-Osc7CurrentDirectory
        if ($script:DotfilesOriginalPrompt) {
            & $script:DotfilesOriginalPrompt
        }
        else {
            "PS $($executionContext.SessionState.Path.CurrentLocation)$('>' * ($nestedPromptLevel + 1)) "
        }
    }
}

# direnv (load .envrc per-directory; must init AFTER prompt hooks above)
# Windows without Nix cannot enter this repository's flake devShell, and
# Windows direnv evaluates .envrc through Git Bash which mutates PATH.
if ((Get-Command direnv -ErrorAction SilentlyContinue) -and (Get-Command nix -ErrorAction SilentlyContinue)) {
    Invoke-Expression (& direnv hook pwsh | Out-String)
}

# qmd (markdown search engine)
$env:QMD_EMBED_MODEL = "hf:Qwen/Qwen3-Embedding-0.6B-GGUF/Qwen3-Embedding-0.6B-Q8_0.gguf"
$env:QMD_RERANK_MODEL = "hf:giladgd/Qwen3-Reranker-4B-GGUF:Q8_0"

# fzf defaults
$env:FZF_DEFAULT_OPTS = "--height=40% --layout=reverse --border --prompt='> '"
if (Get-Command fd -ErrorAction SilentlyContinue) {
    $env:FZF_DEFAULT_COMMAND = "fd --hidden --follow --no-ignore-vcs --max-depth 10 --absolute-path --type f . ."
}

# Interactive widgets (Alt+Q / Alt+D / Alt+T / Alt+R)
# PSReadLine is bundled with the standard PS7 installer; skip the slow -ListAvailable scan.
# On PS7, load failure is unexpected and should surface as an error, not be silently swallowed.
if ($PSVersionTable.PSVersion.Major -ge 7) {
    Import-Module PSReadLine
}

if ((Get-Command fzf -ErrorAction SilentlyContinue) -and (Get-Module PSReadLine)) {
    function Invoke-ZoxideInteractive {
        if (-not (Get-Command zoxide -ErrorAction SilentlyContinue)) { return }
        $result = zoxide query --list --score |
            fzf --height=40% --layout=reverse --border --prompt='z> ' --no-sort --nth=2.. |
            ForEach-Object { ($_ -replace '^\s*[\d.]+\s+', '') }
        if ($result) {
            Set-Location -Path $result
            [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
            [Microsoft.PowerShell.PSConsoleReadLine]::DeleteLine()
            [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
        }
    }

    function Invoke-FzfDirectory {
        if (-not (Get-Command fd -ErrorAction SilentlyContinue)) { return }
        $result = fd --hidden --follow --no-ignore-vcs --max-depth 10 --absolute-path --type d . . | fzf
        if ($result) {
            Set-Location -Path $result
            # Force immediate prompt refresh without extra Enter.
            [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
            [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
        }
    }

    function Invoke-FzfInsertFile {
        if (-not (Get-Command fd -ErrorAction SilentlyContinue)) { return }
        $result = fd --hidden --follow --no-ignore-vcs --max-depth 10 --absolute-path . . | fzf
        if ($result) {
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert($result)
        }
    }

    function Invoke-FzfHistory {
        $result = Get-History |
            Sort-Object -Property Id -Descending |
            Select-Object -ExpandProperty CommandLine -Unique |
            fzf
        if ($result) {
            [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert($result)
        }
    }

    Set-PSReadLineKeyHandler -Chord Alt+q -ScriptBlock { Invoke-ZoxideInteractive }
    Set-PSReadLineKeyHandler -Chord Alt+d -ScriptBlock { Invoke-FzfDirectory }
    Set-PSReadLineKeyHandler -Chord Alt+t -ScriptBlock { Invoke-FzfInsertFile }
    Set-PSReadLineKeyHandler -Chord Alt+r -ScriptBlock { Invoke-FzfHistory }
}

# tm: ghq + fzf でリポジトリ選択 → cd。
# セッション保持は host の Herdr が担当する。
function tm {
    if (-not (Get-Command ghq -ErrorAction SilentlyContinue)) {
        Write-Error "tm: ghq not found. Install with: winget install x-motemen.ghq"
        return
    }
    $repoSlug = ghq list | fzf
    if (-not $repoSlug) { return }
    $repoDir = Join-Path (ghq root) $repoSlug
    Set-Location -Path $repoDir
}

# dotf: run task from dotfiles root without changing cwd
function dotf {
    $dotfilesDir = Split-Path -Parent (chezmoi source-path)
    Push-Location $dotfilesDir
    try { task @args } finally { Pop-Location }
}

# 1Password-managed secrets (GITHUB_PAT_TOKEN, TAVILY_API_KEY, etc.)
# Codex 等の最小環境では $HOME が空文字列のため Join-Path がエラーになる。
if ($HOME) {
    $_secretPs1 = Join-Path $HOME ".config\shell\secret.ps1"
    if (Test-Path $_secretPs1) { . $_secretPs1 }
    Remove-Variable _secretPs1

    $_ghTokenSwitchPs1 = Join-Path $HOME ".config\shell\gh-token-switch.ps1"
    if (Test-Path $_ghTokenSwitchPs1) { . $_ghTokenSwitchPs1 }
    Remove-Variable _ghTokenSwitchPs1
}
