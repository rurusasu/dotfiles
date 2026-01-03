# AGENTS

Purpose: Home Manager zoxide configuration.
Expected contents:
- default.nix: zoxide configuration using programs.zoxide module.
Notes:
- Smart cd command that learns your most used directories
- Replaces cd command with --cmd cd option
- Bash and Zsh integration enabled
Keybindings:
- Alt+Z: Interactive directory selection from history (fzf UI)
Commands:
- cd <keyword>: Jump to best matching directory from history
- cdi: Interactive selection (same as Alt+Z)
