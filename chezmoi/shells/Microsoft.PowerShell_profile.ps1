# PowerShell profile managed by chezmoi

# Rebuild PATH from registry to ensure User PATH is available in elevated sessions.
# Windows Terminal with "elevate: true" may not inherit User-scope PATH entries.
$env:PATH = [Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [Environment]::GetEnvironmentVariable("PATH", "User")

# Aliases
if (Get-Command rg -ErrorAction SilentlyContinue) {
    Set-Alias -Name grep -Value rg -Scope Global
}
if (Get-Command fd -ErrorAction SilentlyContinue) {
    Set-Alias -Name find -Value fd -Scope Global
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

# qmd (markdown search engine)
$env:QMD_EMBED_MODEL = "hf:Qwen/Qwen3-Embedding-0.6B-GGUF/Qwen3-Embedding-0.6B-Q8_0.gguf"
$env:QMD_RERANK_MODEL = "hf:giladgd/Qwen3-Reranker-4B-GGUF:Q8_0"

# fzf defaults
$env:FZF_DEFAULT_OPTS = "--height=40% --layout=reverse --border --prompt='> '"
if (Get-Command fd -ErrorAction SilentlyContinue) {
    $env:FZF_DEFAULT_COMMAND = "fd --hidden --follow --no-ignore-vcs --max-depth 10 --absolute-path --type f . ."
}

# Interactive widgets (Alt+Q / Alt+D / Alt+T / Alt+R)
if (Get-Module -ListAvailable -Name PSReadLine) {
    Import-Module PSReadLine -ErrorAction SilentlyContinue
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

# Ensure CLAUDE_CODE_GIT_BASH_PATH is set for the entire session.
# Claude Code needs this env var to locate bash.exe on Windows.
# Set it at session level so ALL child processes (node, pnpm, etc.) inherit it.
if (-not $env:CLAUDE_CODE_GIT_BASH_PATH) {
    foreach ($_candidate in @(
        (Join-Path $env:LOCALAPPDATA "Programs\Git\bin\bash.exe"),
        "C:\Program Files\Git\bin\bash.exe",
        "C:\Program Files (x86)\Git\bin\bash.exe"
    )) {
        if (Test-Path -LiteralPath $_candidate -PathType Leaf) {
            $env:CLAUDE_CODE_GIT_BASH_PATH = $_candidate
            break
        }
    }
    Remove-Variable _candidate -ErrorAction SilentlyContinue
}

# pnpm global CLI shims
# pnpm's global bin may not be in PATH yet, or Windows shims may not pass env vars.
# Define PowerShell functions that call node + entrypoint directly.
$_pnpmGlobalRoot = $null
try {
    $_pnpmGlobalRoot = (& pnpm root -g 2>$null)
    if ($_pnpmGlobalRoot) { $_pnpmGlobalRoot = $_pnpmGlobalRoot.Trim() }
} catch {}
if ($_pnpmGlobalRoot -and (Test-Path $_pnpmGlobalRoot)) {
    $_pnpmCliShims = @{
        claude = "@anthropic-ai\claude-code\cli.js"
        gemini = "@google\gemini-cli\dist\index.js"
    }
    foreach ($_entry in $_pnpmCliShims.GetEnumerator()) {
        $_entrypoint = Join-Path $_pnpmGlobalRoot $_entry.Value
        if (Test-Path -LiteralPath $_entrypoint -PathType Leaf) {
            $__ep = $_entrypoint
            New-Item -Path "Function:\Global:$($_entry.Key)" -Value (
                [scriptblock]::Create("& node `"$__ep`" @args")
            ) -Force | Out-Null
        }
    }
}
Remove-Variable _pnpmGlobalRoot, _pnpmCliShims, _entry, _entrypoint, __ep -ErrorAction SilentlyContinue

# 1Password-managed secrets (GH_TOKEN, TAVILY_API_KEY, etc.)
$_secretPs1 = Join-Path $HOME ".config\shell\secret.ps1"
if (Test-Path $_secretPs1) { . $_secretPs1 }
Remove-Variable _secretPs1
