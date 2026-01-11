# Windows Terminal Configuration

Windows Terminal is the modern terminal for Windows.

## Files

| File | Deployed To |
|------|-------------|
| `settings.json` | `%LOCALAPPDATA%/Packages/Microsoft.WindowsTerminal.../LocalState/settings.json` |

## Configuration

### Appearance
- **Font**: Consolas, 12pt
- **Opacity**: 85% (acrylic)
- **Color scheme**: One Half Dark (default), CGA (PowerShell)

### Profiles
| Profile | Description |
|---------|-------------|
| PowerShell (default) | PowerShell Core, elevated |
| Windows PowerShell | Legacy PowerShell |
| Git Bash | Git for Windows bash |
| NixOS | WSL NixOS distribution |

## Keybindings

Matches WezTerm keybindings (no leader key support):

### Pane Operations
| Key | Action |
|-----|--------|
| `Ctrl+Alt+H` | Split right |
| `Ctrl+Alt+V` | Split down |
| `Ctrl+Alt+X` | Close pane |
| `Ctrl+Alt+W` | Toggle zoom |

### Pane Navigation
| Key | Action |
|-----|--------|
| `Ctrl+Shift+H` | Focus left |
| `Ctrl+Shift+J` | Focus down |
| `Ctrl+Shift+K` | Focus up |
| `Ctrl+Shift+L` | Focus right |

### Tab Navigation
| Key | Action |
|-----|--------|
| `Ctrl+Tab` | Next tab |
| `Ctrl+Shift+Tab` | Previous tab |

### Other
| Key | Action |
|-----|--------|
| `F11` | Toggle fullscreen |
| `Ctrl+Shift+F` | Find |

### Unbound Keys
- `Alt+C`: Reserved for fzf
- `Alt+Z`: Reserved for zoxide

## Platform

Windows only. Not deployed on Linux/WSL.

## Installation

Pre-installed on Windows 11, or via Microsoft Store.
