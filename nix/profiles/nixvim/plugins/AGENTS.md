# AGENTS

Purpose: Nixvim plugin configurations organized by plugin.

## Structure

```
plugins/
├── default.nix           # Imports all plugin modules
├── AGENTS.md             # This file
├── treesitter/           # Syntax highlighting
│   ├── default.nix
│   └── AGENTS.md
├── telescope/            # Fuzzy finder
│   ├── default.nix
│   └── AGENTS.md
├── lualine/              # Status line
│   ├── default.nix
│   └── AGENTS.md
├── nvim-tree/            # File explorer (tree view)
│   ├── default.nix
│   └── AGENTS.md
├── oil/                  # File explorer (buffer-like)
│   ├── default.nix
│   └── AGENTS.md
├── gitsigns/             # Git integration
│   ├── default.nix
│   └── AGENTS.md
├── indent-blankline/     # Indentation guides
│   ├── default.nix
│   └── AGENTS.md
├── nvim-autopairs/       # Auto bracket pairing
│   ├── default.nix
│   └── AGENTS.md
├── nvim-surround/        # Text surrounding
│   ├── default.nix
│   └── AGENTS.md
├── which-key/            # Keybinding hints
│   ├── default.nix
│   └── AGENTS.md
├── comment/              # Code commenting
│   ├── default.nix
│   └── AGENTS.md
└── web-devicons/         # File type icons
    ├── default.nix
    └── AGENTS.md
```

## Plugin Categories

### UI Enhancement
- `lualine` - Status line
- `indent-blankline` - Indentation guides
- `web-devicons` - File type icons
- `which-key` - Keybinding hints

### Navigation
- `telescope` - Fuzzy finder
- `nvim-tree` - File explorer (tree view)
- `oil` - File explorer (edit filesystem like a buffer)

### Editing
- `nvim-autopairs` - Auto bracket pairing
- `nvim-surround` - Text surrounding
- `comment` - Code commenting

### Syntax & Git
- `treesitter` - Syntax highlighting
- `gitsigns` - Git integration

## Configuration Pattern

Each plugin module follows this pattern:

```nix
{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.myHomeSettings.nixvim;
in
{
  config = mkIf cfg.enable {
    programs.nixvim.plugins.<plugin-name> = {
      enable = true;
      package = pkgs.vimPlugins.<plugin-package>;
      # Additional settings...
    };
  };
}
```

## Conditional Plugins

Some plugins are conditionally enabled:
- `treesitter` - `cfg.features.treesitter`
- `telescope` - `cfg.features.telescope`
- `gitsigns` - `cfg.features.git`

## Adding a New Plugin

1. Create `<plugin-name>/default.nix`
2. Create `<plugin-name>/AGENTS.md` with documentation
3. Add import to `plugins/default.nix`

## Sources

- [Nixvim Docs](https://nix-community.github.io/nixvim/)
- [Nixvim Plugins List](https://nix-community.github.io/nixvim/plugins/)
- [Nixvim GitHub](https://github.com/nix-community/nixvim)
