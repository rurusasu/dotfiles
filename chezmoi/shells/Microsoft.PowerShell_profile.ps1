# PowerShell profile managed by chezmoi

# VS Code Extension Console skips heavy init (starship/zoxide/PSReadLine) to avoid
# session startup timeout. Basic PowerShell functionality (syntax, completion) still works.
if ($env:VSCODE_PID -or $env:VSCODE_INJECTION) { return }

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

# direnv (load .envrc per-directory; must init AFTER prompt hooks above)
if (Get-Command direnv -ErrorAction SilentlyContinue) {
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

# devcontainer: enter the project's devcontainer in a tmux session
# and start nvim inside it. Terminal-agnostic mirror of the zsh/bash
# `dcnvim` defined in nix/home/common.nix.
# Re-running attaches to the existing tmux session so nvim state
# survives terminal close.
#
# Session name policy mirrors `tm` (Linux): if the workspace lives
# under ghq root, use the slug basename (e.g. ghq/github.com/foo/bar
# -> "bar"); otherwise fall back to the workspace folder basename.
#
# Usage: dcnvim [-Workspace <path>]   # defaults to $PWD
#
# Requires: @devcontainers/cli on host; bootstrap.sh ran inside the
# container to provide nvim + tmux. See bootstrap.sh at repo root.
function dcnvim {
    [CmdletBinding()]
    param([string]$Workspace = (Get-Location).Path)

    if (-not (Get-Command devcontainer -ErrorAction SilentlyContinue)) {
        Write-Error "dcnvim: devcontainer CLI not found. Install with: npm i -g @devcontainers/cli"
        return
    }
    if (-not (Test-Path (Join-Path $Workspace ".devcontainer")) -and
        -not (Test-Path (Join-Path $Workspace ".devcontainer.json"))) {
        Write-Error "dcnvim: no .devcontainer/ or .devcontainer.json under $Workspace"
        return
    }

    # Resolve session name. ghq slug basename if under ghq root, else
    # workspace basename. Mirrors _dcnvim_session_name in
    # nix/home/dcnvim-session-name.sh.
    $sessionName = $null
    if (Get-Command ghq -ErrorAction SilentlyContinue) {
        $ghqRoot = (& ghq root 2>$null | Select-Object -First 1)
        if ($ghqRoot) {
            $ghqRoot = $ghqRoot.TrimEnd('/', '\')
            $wsAbs = (Resolve-Path -LiteralPath $Workspace).Path.TrimEnd('/', '\')
            $wsNorm = $wsAbs -replace '\\', '/'
            $rootNorm = $ghqRoot -replace '\\', '/'
            if ($wsNorm.StartsWith("$rootNorm/")) {
                $slug = $wsNorm.Substring($rootNorm.Length + 1)
                $sessionName = ($slug -split '/')[-1]
            }
        }
    }
    if (-not $sessionName) {
        $sessionName = Split-Path -Leaf $Workspace.TrimEnd('/', '\')
    }

    # bash -l reads ~/.profile (not ~/.bashrc); export PATH inline so the
    # container's just-bootstrapped ~/.local/bin/nvim is found. nvim/tmux
    # presence is checked explicitly because tmux exits 0 if its child
    # command is missing, masking the failure to the host.
    # Use double-quoted here-string so $sessionName interpolates; escape
    # bash variables with backtick so they stay literal for the shell.
    $payload = @"
export PATH="`$HOME/.local/bin:`$PATH"
command -v nvim >/dev/null 2>&1 || {
  echo 'dcnvim: nvim not installed in container — run ~/.dotfiles/bootstrap.sh first' >&2
  exit 127
}
command -v tmux >/dev/null 2>&1 || {
  echo 'dcnvim: tmux not installed in container — run ~/.dotfiles/bootstrap.sh first' >&2
  exit 127
}
tmux new -A -s '$sessionName' 'nvim .'
"@

    & devcontainer exec --workspace-folder $Workspace -- bash -lc $payload
}

# tm: ghq + fzf でリポジトリ選択 → cd (Windows 版: tmux なし)
function tm {
    if (-not (Get-Command ghq -ErrorAction SilentlyContinue)) {
        Write-Error "tm: ghq not found. Install with: winget install x-motemen.ghq"
        return
    }
    $result = ghq list --full-path | fzf
    if ($result) {
        Set-Location -Path $result
    }
}

# dotf: run task from dotfiles root without changing cwd
function dotf {
    $dotfilesDir = Split-Path -Parent (chezmoi source-path)
    Push-Location $dotfilesDir
    try { task @args } finally { Pop-Location }
}

# 1Password-managed secrets (GH_TOKEN, TAVILY_API_KEY, etc.)
$_secretPs1 = Join-Path $HOME ".config\shell\secret.ps1"
if (Test-Path $_secretPs1) { . $_secretPs1 }
Remove-Variable _secretPs1
