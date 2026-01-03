# AGENTS

Purpose: Windows Terminal configuration via Nix.
Expected contents:
- default.nix: Settings defined as Nix expression, generates JSON
Notes:
- Settings exported to ~/.config/windows-terminal/settings.json
- Alt+C and Alt+Z unbound for fzf integration
- Default profile: PowerShell Core (elevated)
- Apply to Windows: windows/scripts/apply-settings.ps1 -UseNixGenerated
