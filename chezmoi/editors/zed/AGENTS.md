# Zed Configuration

Zed is a high-performance, native code editor.

## Files

| File | Deployed To | Purpose |
|------|-------------|---------|
| `settings.json` | `~/.config/zed/` or `%APPDATA%/Zed/` | Editor settings |
| `keymap.json` | Same as above | Custom keybindings |

## Configuration Format

Zed uses JSONC (JSON with comments). Settings syntax differs from VS Code.

## Settings Highlights

### Appearance
- Theme: Gruvbox Dark Hard
- Font: Consolas, 12pt
- UI font size: 14pt

### Editor
- Tab size: 2 spaces
- Vim mode: Enabled
- Relative line numbers: Enabled
- Format on save: Enabled

### Vim Mode
```json
"vim_mode": true,
"vim": {
  "use_system_clipboard": "always"
}
```

### Terminal
- Shell: pwsh (PowerShell)
- Font size: 13pt

### Language Formatters
| Language | Formatter |
|----------|-----------|
| Python | Ruff (external) |
| JavaScript/TypeScript | Prettier |

## Keybindings

### Pane Operations (matches WezTerm/WT)
| Key | Action |
|-----|--------|
| `Ctrl+Alt+H` | Split right |
| `Ctrl+Alt+V` | Split down |
| `Ctrl+Alt+X` | Close item |
| `Ctrl+Alt+W` | Toggle zoom |
| `Ctrl+Shift+H/J/K/L` | Navigate panes |

### Vim Normal Mode
| Key | Action |
|-----|--------|
| `Space+F+F` | File finder |
| `Space+F+G` | Search in project |
| `Space+E` | Toggle file tree |

## Installation

- **Linux/WSL**: `nix` (zed-editor package)
- **Windows**: `winget install Zed.Zed`

## Extensions

Zed uses built-in language support. No extension management needed.
