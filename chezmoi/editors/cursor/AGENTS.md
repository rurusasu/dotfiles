# Cursor Configuration

Cursor is an AI-powered code editor (VS Code fork).

## Files

| File | Deployed To | Purpose |
|------|-------------|---------|
| `settings.json` | `~/.config/Cursor/User/` or `%APPDATA%/Cursor/User/` | Editor settings |
| `keybindings.json` | Same as above | Custom keybindings |
| `extensions.json` | N/A (used by script) | Extension list |

## Configuration

Cursor uses the same configuration format as VS Code. Settings are largely identical with Cursor-specific additions:
- `cursor.cpp.disabledLanguages`: []
- `cursor.general.enableShadowWorkspace`: true

## Settings

Inherited from VS Code configuration:
- Vim mode with relative line numbers
- Format on save
- Prettier/Ruff formatters
- Material Icon Theme

## Extensions

Same extensions as VS Code, installed via `cursor --install-extension`.

## AI Features

Cursor's AI features are configured through the app itself, not settings files.

## Installation

- **Linux**: AppImage or download from cursor.sh
- **Windows**: `winget install Anysphere.Cursor`

## Note

Cursor is not available in nixpkgs. Install manually or via package manager.
