# secret

Purpose: Shell-startup secret injection via 1Password CLI.
Expected contents:

- env.sh: Bash/Zsh secret loader (GH_TOKEN, TAVILY_API_KEY via `op read`).
- env.ps1: PowerShell secret loader (same secrets).

Notes:

- Deployed to `~/.config/shell/secret.sh` and `~/.config/shell/secret.ps1`.
- Sourced by .bashrc, .zshrc, and Microsoft.PowerShell_profile.ps1.
- No actual secrets stored here — only `op://` references resolved at runtime.
- Covers: Linux bash/zsh, WSL NixOS, Git Bash (Windows), PowerShell.
- `op://` paths must be updated to match your 1Password vault items.
