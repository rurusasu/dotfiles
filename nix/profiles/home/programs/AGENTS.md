# AGENTS

Purpose: tool-specific Home Manager modules and package list.
Expected contents:
- default.nix: imports remaining program modules and installs packages for chezmoi-managed config.
- ghq/: ghq module (package install).
- tmux/: tmux module.
- vscode/: VS Code module (extensions only; settings/keybindings in chezmoi).
Notes:
- Shells, git, starship, fzf/fd/ripgrep/zoxide, LLM, and terminal configs are managed by chezmoi.
- Imported from profiles/home/default.nix.
