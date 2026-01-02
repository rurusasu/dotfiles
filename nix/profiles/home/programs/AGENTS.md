# AGENTS

Purpose: tool-specific Home Manager modules.
Expected contents:
- vscode/: VS Code module (default.nix, settings.nix, keybindings.json).
- wezterm/: WezTerm module (default.nix, wezterm.lua).
- fzf/: fzf module (default.nix).
Notes:
- Each tool has its own directory with default.nix and config files.
- Imported from common.nix.
