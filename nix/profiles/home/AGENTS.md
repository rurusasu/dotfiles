# AGENTS

Purpose: Home Manager profiles and source files.
Expected contents:
- common.nix: shared Home Manager settings imported by all hosts.
- bash/: .bashrc, .profile, .bash_logout (source files).
- programs/: tool-specific Home Manager modules (vscode/, wezterm/).
Notes:
- nixvim config is in profiles/nixvim/, imported from common.nix.
