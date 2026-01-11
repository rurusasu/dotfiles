# Chezmoi source

This directory holds chezmoi-managed user dotfiles.

This repo intentionally deploys most files via `.chezmoiscripts/run_onchange_deploy.*` and ignores the top-level directories via `.chezmoiignore`.

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
