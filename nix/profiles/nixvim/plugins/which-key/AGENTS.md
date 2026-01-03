# AGENTS

Purpose: which-key keybinding hints popup configuration.

## Nixvim Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | false | Enable which-key |
| `package` | package | pkgs.vimPlugins.which-key-nvim | Package |
| `autoLoad` | bool | true | Auto load on startup |
| `settings` | attrs | {} | Options for `require('which-key').setup` |
| `settings.delay` | int | 200 | Delay before popup (ms) |
| `settings.icons.mappings` | bool | true | Show mapping icons |
| `settings.icons.keys` | attrs | {} | Key icons |
| `settings.win.border` | string | "none" | Window border style |
| `settings.win.padding` | list | [1,2] | Window padding |
| `settings.layout.spacing` | int | 3 | Column spacing |

## Current Configuration

```nix
plugins.which-key = {
  enable = true;
  package = pkgs.vimPlugins.which-key-nvim;
};
```

## Features

- Shows keybinding hints in a popup window
- Groups related keybindings
- Automatically detects key sequences
- Integrates with other plugins

## Sources

- [Nixvim which-key Docs](https://nix-community.github.io/nixvim/plugins/which-key/index.html)
- [which-key.nvim GitHub](https://github.com/folke/which-key.nvim)
