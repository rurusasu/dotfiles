# Neovim Configuration

Neovim configuration using lazy.nvim plugin manager.

## Structure

```
nvim/
├── init.lua              # Entry point, lazy.nvim bootstrap
└── lua/
    ├── config/
    │   ├── options.lua   # Core vim options
    │   └── keymaps.lua   # Key mappings
    └── plugins/
        └── init.lua      # Plugin specifications
```

## Plugin Manager

Uses [lazy.nvim](https://github.com/folke/lazy.nvim) for plugin management.
Plugins are lazy-loaded by default for fast startup.

## Included Plugins

| Plugin              | Purpose              |
| ------------------- | -------------------- |
| gruvbox.nvim        | Color scheme         |
| oil.nvim            | File explorer        |
| telescope.nvim      | Fuzzy finder         |
| nvim-treesitter     | Syntax highlighting  |
| lualine.nvim        | Status line          |
| gitsigns.nvim       | Git integration      |
| which-key.nvim      | Key binding help     |
| Comment.nvim        | Commenting           |
| nvim-autopairs      | Auto pairs           |
| nvim-surround       | Surround editing     |
| indent-blankline    | Indent guides        |

## Key Mappings

Leader key: `<Space>`

| Key           | Action              |
| ------------- | ------------------- |
| `<leader>e`   | File explorer (Oil) |
| `<leader>ff`  | Find files          |
| `<leader>fg`  | Live grep           |
| `<leader>fb`  | Buffers             |
| `<leader>w`   | Save file           |
| `<leader>q`   | Quit                |

## Deployment

Deployed to `~/.config/nvim/` on Linux/WSL.
