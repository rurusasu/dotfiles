# AGENTS

Purpose: Neovim configuration via nixvim module.

## Structure

```
nixvim/
  default.nix   # Nixvim configuration (uses mkIf cfg.enable)
  init.lua      # Extra Lua config (VSCode integration, etc.)
```

## Options Location

Options are defined in `nix/modules/home/nixvim/default.nix`.

## Shared Settings

Nixvim uses module options for configuration:

```nix
myHomeSettings.nixvim = {
  enable = true;
  leader = " ";                    # Space (Vim leader)
  colorscheme.name = "tokyonight";
  colorscheme.style = "night";
  features = {
    lsp = true;
    treesitter = true;
    telescope = true;
    git = true;
  };
};
```

## Options

| Option | Default | Description |
|--------|---------|-------------|
| `enable` | `false` | Enable nixvim |
| `leader` | `" "` (Space) | Vim leader key |
| `localLeader` | `\` | Local leader key |
| `colorscheme.name` | `tokyonight` | Colorscheme |
| `colorscheme.style` | `night` | Colorscheme style |
| `features.lsp` | `true` | Enable LSP |
| `features.treesitter` | `true` | Enable Treesitter |
| `features.telescope` | `true` | Enable Telescope |
| `features.git` | `true` | Enable Git integration |

## Notes

- Uses nixvim native plugin system (Nix manages plugins, not lazy.nvim)
- byteCompileLua enabled for faster startup
- Supports both native Neovim and VSCode Neovim integration
- Leader key set via Nix module, not init.lua

## Plugins

| Plugin | Description | Keybinding |
|--------|-------------|------------|
| tokyonight | Colorscheme (night style) | - |
| which-key | Keybinding hints | - |
| nvim-tree | File explorer | `<leader>e` |
| telescope | Fuzzy finder | `<leader>ff/fg/fb/fh` |
| treesitter | Syntax highlighting | - |
| gitsigns | Git integration | - |
| lualine | Status line | - |
| indent-blankline | Indent guides | - |
| nvim-autopairs | Auto pairs | - |
| comment | Commenting | `gc`, `gb` |
| nvim-surround | Surround operations | - |
| web-devicons | File icons | - |

See `nix/modules/home/AGENTS.md` for full shared settings architecture.
