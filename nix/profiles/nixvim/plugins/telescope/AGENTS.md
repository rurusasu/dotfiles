# AGENTS

Purpose: Telescope fuzzy finder configuration.

## Nixvim Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | false | Enable telescope |
| `package` | package | pkgs.vimPlugins.telescope-nvim | Telescope package |
| `autoLoad` | bool | true | Auto load on startup |
| `keymaps` | attrs | {} | Keymap definitions |
| `settings` | attrs | {} | Options for `require('telescope').setup` |
| `extensions.<name>.enable` | bool | false | Enable telescope extensions |

## Current Configuration

```nix
plugins.telescope = {
  enable = true;
  package = pkgs.vimPlugins.telescope-nvim;
  keymaps = {
    "<leader>ff" = { action = "find_files"; options.desc = "Find files"; };
    "<leader>fg" = { action = "live_grep"; options.desc = "Live grep"; };
    "<leader>fb" = { action = "buffers"; options.desc = "Buffers"; };
    "<leader>fh" = { action = "help_tags"; options.desc = "Help tags"; };
  };
};
```

## Available Extensions

- `file-browser` - File browser integration
- `fzf-native` - FZF sorter for performance
- `ui-select` - vim.ui.select replacement
- `frecency` - Frequency-based file sorting

## Sources

- [Nixvim Telescope Docs](https://nix-community.github.io/nixvim/plugins/telescope/index.html)
- [Telescope Extensions](https://nix-community.github.io/nixvim/plugins/telescope/extensions/file-browser/index.html)
- [telescope.nvim GitHub](https://github.com/nvim-telescope/telescope.nvim)
