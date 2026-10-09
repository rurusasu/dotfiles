# Chezmoi source

This directory holds chezmoi-managed user dotfiles.

Windows uses the existing dotfiles and PowerShell deployment scripts.
On macOS, Linux, and WSL, chezmoi deploys only `.codex/` and `.claude/`;
all other user configuration belongs to Home Manager. Unix has no deployment
scripts. `.claude/` is reserved for future settings; no Claude configuration
is currently present in this repository.

Initialize/apply:

chezmoi init --source ~/.dotfiles/chezmoi
chezmoi apply

Windows example:

chezmoi init --source "D:/my_programing/dotfiles/chezmoi"
chezmoi apply

Secrets:

- Configure age/gpg in ~/.config/chezmoi/chezmoi.toml
- On Windows, use forward slashes (`D:/...`) or escape backslashes (`D:\\...`) in TOML strings.
- Add/update secrets with: chezmoi add --encrypt <path>
