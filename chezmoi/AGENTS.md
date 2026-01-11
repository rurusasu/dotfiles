# Chezmoi Dotfiles

Cross-platform dotfiles management using chezmoi.

## Directory Structure

```
chezmoi/
├── shells/      # Shell configurations (bash, zsh, profile)
├── git/         # Git configuration
├── cli/         # CLI tool configurations (fd, ripgrep, starship, ghq, zoxide)
├── terminals/   # Terminal emulator configurations (wezterm, windows-terminal)
├── editors/     # Editor configurations (vscode, cursor, zed)
├── llms/        # LLM tool configs (claude/codex/cursor/gemini)
├── github/      # GitHub configs (workflows, templates, etc)
├── ssh/         # SSH config templates
└── .chezmoiscripts/  # Deployment scripts
```

## Architecture

### Deployment Method
All configurations are deployed via `.chezmoiscripts/run_onchange_deploy.*`:
- `run_onchange_deploy.ps1` - Windows (PowerShell)
- `run_onchange_deploy.sh` - Unix/Linux/WSL/DevContainer

### Role Separation
| Role | Tool |
|------|------|
| **Installation** | Nix (Linux/WSL), winget (Windows) |
| **Configuration** | Chezmoi (this directory) |
| **Shell Integration** | Nix Home Manager (fzf, zoxide) |

## Usage

```bash
# Initialize chezmoi
chezmoi init --source ~/.dotfiles/chezmoi

# Apply configurations
chezmoi apply
```

Windows (example):

```powershell
chezmoi init --source "D:/my_programing/dotfiles/chezmoi"
chezmoi apply
```

## Adding New Configurations

1. Create appropriate subdirectory under the relevant category
2. Add configuration files
3. Update deployment scripts if needed
4. All directories are ignored by chezmoi (see `.chezmoiignore`) and deployed via scripts

Notes:
- `AGENTS.md` / `README.md` are intentionally ignored (docs only)

## Platform Support

- Windows (native)
- Linux
- WSL (Windows Subsystem for Linux)
- DevContainer
