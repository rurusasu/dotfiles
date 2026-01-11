# VS Code Configuration

Visual Studio Code editor configuration.

## Files

| File | Deployed To | Purpose |
|------|-------------|---------|
| `settings.json` | `~/.config/Code/User/` or `%APPDATA%/Code/User/` | Editor settings |
| `keybindings.json` | Same as above | Custom keybindings |
| `extensions.json` | N/A (used by script) | Extension list |

## Settings Highlights

### Editor
- Font size: 12pt
- Tab size: 2 spaces
- Format on save: Enabled
- Line numbers: Relative (vim mode)
- Word wrap: 80 columns

### Theme
- Color theme: Default Dark Modern
- Icon theme: Material Icon Theme

### Vim Mode
- System clipboard: Enabled
- Leader key: `<Space>`
- Disabled Ctrl keys: `Ctrl+A/C/V/X/Z` (OS compatibility)
- Enabled Ctrl keys: `Ctrl+D/U/F/B/O` (vim navigation)

### Language Formatters
| Language | Formatter |
|----------|-----------|
| Python | Ruff |
| JavaScript/TypeScript | Prettier |
| JSON | Prettier |

## Extensions

Auto-installed extensions:
- `tobiasalthoff.atom-material-theme`
- `ms-vscode-remote.remote-containers`
- `ms-vscode-remote.remote-ssh`
- `vscodevim.vim`
- `esbenp.prettier-vscode`
- `charliermarsh.ruff`
- And more (see `extensions.json`)

## Installation

- **Linux/WSL**: `nix` (programs.vscode)
- **Windows**: `winget install Microsoft.VisualStudioCode`

## Remote Development

Configured for:
- Dev Containers
- SSH Remote
- WSL
