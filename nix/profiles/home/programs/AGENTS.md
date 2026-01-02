# AGENTS

Purpose: tool-specific Home Manager modules.
Expected contents:
- default.nix: imports all program modules.
- claude-code/: claude-code and codex module.
- fonts/: font packages module.
- fzf/: fzf module.
- ghq/: ghq module.
- git/: git module.
- tmux/: tmux module.
- vscode/: VS Code module (default.nix, settings.json, keybindings.json).
- wezterm/: WezTerm module (default.nix, wezterm.lua).
- zsh/: zsh module with shell aliases.
Notes:
- Each tool has its own directory with default.nix and config files.
- Imported from profiles/home/default.nix.
