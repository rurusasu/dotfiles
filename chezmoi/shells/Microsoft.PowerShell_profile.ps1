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

# VS Code Extension Console skips heavy init (starship/zoxide/PSReadLine) to avoid
# session startup timeout. Basic PowerShell functionality (syntax, completion) still works.
if ($env:VSCODE_PID -or $env:VSCODE_INJECTION) { return }

# Rebuild PATH from registry to ensure User PATH is available in elevated sessions.
# Windows Terminal with "elevate: true" may not inherit User-scope PATH entries.
$env:PATH = [Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [Environment]::GetEnvironmentVariable("PATH", "User")

# Tell snacks.nvim to use WezTerm's Kitty graphics protocol for image preview.
$env:SNACKS_WEZTERM = "true"

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
    # Codex 等の最小環境で起動された場合 $env:LOCALAPPDATA が null になるため Join-Path がエラーになる。
    $_candidates = [System.Collections.Generic.List[string]]::new()
    if ($env:LOCALAPPDATA) {
        $_candidates.Add((Join-Path $env:LOCALAPPDATA "Programs\Git\bin\bash.exe"))
    }
    $_candidates.Add("C:\Program Files\Git\bin\bash.exe")
    $_candidates.Add("C:\Program Files (x86)\Git\bin\bash.exe")
    foreach ($_candidate in $_candidates) {
        if (Test-Path -LiteralPath $_candidate -PathType Leaf) {
            $env:CLAUDE_CODE_GIT_BASH_PATH = $_candidate
            break
        }
    }
    Remove-Variable _candidate, _candidates -ErrorAction SilentlyContinue
}

# devcontainer: enter the project's devcontainer in a tmux session
# and start nvim inside it. Terminal-agnostic mirror of the zsh/bash
# POSIX `dcnvim` defined in scripts/sh/dcnvim.sh.
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
function ConvertTo-DcnvimBashSingleQuoted {
    param([Parameter(Mandatory)][string]$Value)

    return "'" + $Value.Replace("'", "'\''") + "'"
}

function dcnvim {
    [CmdletBinding()]
    param([string]$Workspace = "")

    # No arg + cwd has .devcontainer  → use cwd
    # No arg + no .devcontainer       → ghq list | fzf picker
    # Explicit path                   → use that path
    if (-not $Workspace) {
        $cwd = (Get-Location).Path
        if ((Test-Path (Join-Path $cwd ".devcontainer")) -or (Test-Path (Join-Path $cwd ".devcontainer.json"))) {
            $Workspace = $cwd
        }
        elseif ((Get-Command ghq -ErrorAction SilentlyContinue) -and (Get-Command fzf -ErrorAction SilentlyContinue)) {
            $selected = ghq list | fzf --prompt="devcontainer> "
            if (-not $selected) { return }
            $Workspace = Join-Path (ghq root) $selected
        }
        else {
            $Workspace = $cwd
        }
    }

    try {
        $Workspace = (Resolve-Path -LiteralPath $Workspace -ErrorAction Stop).Path
    }
    catch {
        Write-Error "dcnvim: workspace not found: $Workspace"
        return
    }

    if (-not (Get-Command devcontainer -ErrorAction SilentlyContinue)) {
        Write-Error "dcnvim: devcontainer CLI not found. Install with: npm i -g @devcontainers/cli"
        return
    }
    if (-not (Test-Path (Join-Path $Workspace ".devcontainer")) -and
        -not (Test-Path (Join-Path $Workspace ".devcontainer.json"))) {
        Write-Error "dcnvim: no .devcontainer/ or .devcontainer.json under $Workspace"
        return
    }

    # Bring container up + inject dotfiles. CLI does not read
    # ~/.config/devcontainer/devcontainer.json (that's a VS Code extension
    # config), so dotfiles flags must be passed explicitly. Idempotent.
    $dotfilesUrl = if ($env:DOTFILES_REPOSITORY_URL) {
        $env:DOTFILES_REPOSITORY_URL
    }
    else {
        'https://github.com/rurusasu/dotfiles'
    }
    & devcontainer up `
        --workspace-folder $Workspace `
        --dotfiles-repository $dotfilesUrl `
        --dotfiles-install-command bootstrap.sh | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "dcnvim: devcontainer up failed (exit $LASTEXITCODE)"
        return
    }

    # Resolve session name. ghq slug basename if under ghq root, else
    # workspace basename. Mirrors _dcnvim_session_name in
    # scripts/sh/dcnvim.sh.
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
        $wsAbs = (Resolve-Path -LiteralPath $Workspace).Path
        $sessionName = Split-Path -Leaf $wsAbs.TrimEnd('/', '\')
    }
    $sessionNameQuoted = ConvertTo-DcnvimBashSingleQuoted $sessionName

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
tmux new -A -s $sessionNameQuoted 'nvim .'
"@

    & devcontainer exec --workspace-folder $Workspace -- bash -lc $payload
}

# tm: ghq + fzf でリポジトリ選択 → cd。
# 選択先に .devcontainer/ または .devcontainer.json があれば
# 自動で dcnvim を起動して container 開発に入る。
# Linux 版 tm (nix/home/common.nix) は host tmux に attach するが、
# Windows host には tmux が無いため、container 開発の入口として動く。
function tm {
    if (-not (Get-Command ghq -ErrorAction SilentlyContinue)) {
        Write-Error "tm: ghq not found. Install with: winget install x-motemen.ghq"
        return
    }
    $repoSlug = ghq list | fzf
    if (-not $repoSlug) { return }
    $repoDir = Join-Path (ghq root) $repoSlug
    Set-Location -Path $repoDir

    if ((Test-Path .devcontainer) -or (Test-Path .devcontainer.json)) {
        dcnvim
    }
}

# dotf: run task from dotfiles root without changing cwd
function dotf {
    $dotfilesDir = Split-Path -Parent (chezmoi source-path)
    Push-Location $dotfilesDir
    try { task @args } finally { Pop-Location }
}

# claude: intercept `claude update` to run pnpm install + postinstall.
# pnpm v10 blocks build scripts by default, so the native binary postinstall
# never runs when using `claude update` directly, leaving a stub exe.
function claude {
    if ($args[0] -eq 'update') {
        pnpm install -g "@anthropic-ai/claude-code@latest"
        if ($LASTEXITCODE -eq 0) {
            $pkgDir = Join-Path (pnpm root -g).Trim() "@anthropic-ai\claude-code"
            Push-Location $pkgDir
            try { node install.cjs } finally { Pop-Location }
        }
        return
    }
    $ps1 = Get-Command claude -CommandType ExternalScript -ErrorAction SilentlyContinue | Where-Object { $_.Source -like '*\pnpm\*' } | Select-Object -First 1
    if ($ps1) { & $ps1.Source @args } else { & claude.exe @args }
}

# 1Password-managed secrets (GH_TOKEN, TAVILY_API_KEY, etc.)
# Codex 等の最小環境では $HOME が空文字列のため Join-Path がエラーになる。
if ($HOME) {
    $_secretPs1 = Join-Path $HOME ".config\shell\secret.ps1"
    if (Test-Path $_secretPs1) { . $_secretPs1 }
    Remove-Variable _secretPs1

    $_ghTokenSwitchPs1 = Join-Path $HOME ".config\shell\gh-token-switch.ps1"
    if (Test-Path $_ghTokenSwitchPs1) { . $_ghTokenSwitchPs1 }
    Remove-Variable _ghTokenSwitchPs1
}
