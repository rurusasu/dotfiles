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
- Windows Terminal settings are managed in Nix at `nix/profiles/home/programs/terminals/windows-terminal/`
- WezTerm settings are managed in Nix at `nix/profiles/home/programs/terminals/wezterm/`
- All scripts are in `scripts/` directory (see [scripts/AGENTS.md](../scripts/AGENTS.md))
