# Editor Configurations

Code editor configurations for cross-platform development.

## Editors

| Editor | Config Path | Based On |
|--------|-------------|----------|
| VS Code | `vscode/` | - |
| Cursor | `cursor/` | VS Code fork |
| Zed | `zed/` | Native |

## Files Per Editor

### VS Code / Cursor (VS Code-based)
| File | Purpose |
|------|---------|
| `settings.json` | Editor settings |
| `keybindings.json` | Custom keybindings |
| `extensions.json` | Extension list (auto-installed) |

### Zed
| File | Purpose |
|------|---------|
| `settings.json` | Editor settings (JSONC format) |
| `keymap.json` | Custom keybindings |

## Deployment Paths

| Editor | Windows | Linux/WSL |
|--------|---------|-----------|
| VS Code | `%APPDATA%/Code/User/` | `~/.config/Code/User/` |
| Cursor | `%APPDATA%/Cursor/User/` | `~/.config/Cursor/User/` |
| Zed | `%APPDATA%/Zed/` | `~/.config/zed/` |

## Common Settings

### Editor Behavior
- **Font size**: 12pt
- **Tab size**: 2 spaces
- **Format on save**: Enabled
- **Line numbers**: Relative (vim mode)
- **Word wrap**: On (80 columns)

### Theme
- **Color theme**: Default Dark Modern / Gruvbox
- **Icon theme**: Material Icon Theme

### Vim Mode
All editors configured with vim keybindings:
- System clipboard integration
- Leader key: `<Space>`
- Common Ctrl keys disabled for OS compatibility

### Language-specific
- **Python**: Ruff formatter
- **JavaScript/TypeScript/JSON**: Prettier

## Extension Management

VS Code and Cursor extensions are:
1. Listed in `extensions.json`
2. Auto-installed by deployment scripts via CLI
3. Checked before install (skip if already installed)

## Installation

| Editor | Windows | Linux/WSL |
|--------|---------|-----------|
| VS Code | winget | Nix |
| Cursor | winget | AppImage |
| Zed | winget | Nix (`zed-editor`) |
