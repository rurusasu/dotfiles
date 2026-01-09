# AGENTS

Purpose
- Windows-side configuration files.

## Directory Structure
```
windows/
├── winget/      # Package management (winget export/import)
└── .wslconfig   # WSL configuration
```

Note:
- Windows Terminal settings are managed by chezmoi at `chezmoi/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json`
- WezTerm settings are managed by chezmoi at `chezmoi/dot_config/wezterm/wezterm.lua`
- All scripts are in `scripts/` directory (see [scripts/AGENTS.md](../scripts/AGENTS.md))
