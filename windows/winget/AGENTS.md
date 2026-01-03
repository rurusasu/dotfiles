# AGENTS

Purpose: Windows package management via winget.
Expected contents:
- packages.json: Exported winget package list
Notes:
- Export: winget export -o packages.json
- Import: winget import -i packages.json --accept-package-agreements
- Some packages may require manual installation (license agreements, unavailable sources)
- Use scripts/export-settings.ps1 to update package list
- Use scripts/apply-settings.ps1 to install packages
