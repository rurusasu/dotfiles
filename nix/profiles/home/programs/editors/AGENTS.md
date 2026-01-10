# Editors Profile

Nix Home Manager configuration for code editors.

## Structure

```
editors/
├── default.nix    # Imports all editor modules
├── vscode/        # VS Code configuration
├── cursor/        # Cursor configuration
└── zed/           # Zed configuration
```

## Role Separation

| Aspect | Managed By |
|--------|------------|
| **Installation** | Nix (this directory) |
| **Settings/Keybindings** | Chezmoi (`chezmoi/editors/`) |
| **Extensions** | Chezmoi (`extensions.json`) |

## Editors

### VS Code
- Installed via `programs.vscode`
- `mutableExtensionsDir = true` (extensions managed by chezmoi)

### Cursor
- Not in nixpkgs
- Install manually (winget on Windows, AppImage on Linux)

### Zed
- Installed via `home.packages = [ zed-editor ]`

## Usage

This profile is imported by `profiles/home/default.nix`.

## See Also

- `chezmoi/editors/` - Settings and extensions
- `chezmoi/editors/AGENTS.md` - Chezmoi editor configuration docs
