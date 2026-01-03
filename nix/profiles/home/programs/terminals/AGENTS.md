# AGENTS

Purpose: Terminal emulator configurations.
Expected contents:
- wezterm/: WezTerm configuration (cross-platform)
- windows-terminal/: Windows Terminal configuration (Nix-generated)
Notes:
- Both terminals configured for fzf Alt+C/Alt+Z keybindings
- WezTerm: Native Home Manager module
- Windows Terminal: Nix generates JSON, applied via PowerShell symlink
