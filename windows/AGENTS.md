# AGENTS

Purpose

- Windows-side configuration files.

## Directory Structure

```
windows/
├── winget/                  # Package management (winget export/import)
├── npm/                     # npm global packages (packages.json)
├── bun/                     # bun global packages (packages.json)
├── .wslconfig               # WSL configuration
├── .wslconfig.example       # WSL config template/example
├── docker-vhd-size.conf     # Docker VHD size configuration
└── expand-docker-vhd.ps1   # Script to expand Docker VHD
```

Note:

- Windows Terminal settings are managed by chezmoi at `chezmoi/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json`
- WezTerm settings are managed by chezmoi at `chezmoi/terminals/wezterm/wezterm.lua`
- All scripts are in `scripts/` directory (see [scripts/AGENTS.md](../scripts/AGENTS.md))
