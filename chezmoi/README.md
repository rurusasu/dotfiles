# Chezmoi source

This directory holds chezmoi-managed user dotfiles.

Initialize/apply:

  chezmoi init --source ~/.dotfiles/chezmoi
  chezmoi apply

Secrets:
- Configure age/gpg in ~/.config/chezmoi/chezmoi.toml
- Add/update secrets with: chezmoi add --encrypt <path>
