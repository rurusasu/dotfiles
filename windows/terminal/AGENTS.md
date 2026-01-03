# AGENTS

Purpose: Windows Terminal configuration.
Expected contents:
- settings.json: Windows Terminal settings (symlink source)
Notes:
- Managed via symlink to %LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json
- Alt+C unbound for fzf compatibility in WSL
- Use scripts/apply-settings.ps1 to create symlink
- Use scripts/export-settings.ps1 to update from current settings
