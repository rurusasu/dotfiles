# VS Code Configuration

Visual Studio Code editor configuration.

## Documentation

- [Keybinding Policy](../../../docs/chezmoi/keybindings.md)

## Files

| File               | Deployed To                                      | Purpose            |
| ------------------ | ------------------------------------------------ | ------------------ |
| `settings.json`    | `~/.config/Code/User/` or `%APPDATA%/Code/User/` | Editor settings    |
| `keybindings.json` | Same as above                                    | Custom keybindings |
| `extensions.json`  | N/A (used by script)                             | Extension list     |

## Settings Highlights

### Editor

- Font size: 12pt
- Tab size: 2 spaces
- Format on save: Enabled
- Line numbers: On
- Word wrap: 80 columns

### Theme

- Color theme: Default Dark Modern
- Icon theme: Material Icon Theme

### Keybinding Policy

- Follow `docs/chezmoi/keybindings.md`
- Prefer editor-native shortcuts
- VS Code Vim extension is not required

### Language Formatters

| Language              | Formatter |
| --------------------- | --------- |
| Python                | Ruff      |
| JavaScript/TypeScript | Prettier  |
| JSON                  | Prettier  |

## Extensions

Auto-installed extensions:

- `tobiasalthoff.atom-material-theme`
- `ms-vscode-remote.remote-containers`
- `ms-vscode-remote.remote-ssh`
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
