# AGENTS

Purpose: Neovim configuration via nixvim module.
Expected contents:
- default.nix: programs.nixvim settings with native plugin configuration.
- init.lua: Lua configuration loaded via extraConfigLua.
Notes:
- Uses nixvim native plugin system (Nix manages plugins, not lazy.nvim)
- byteCompileLua enabled for faster startup
- Supports both native Neovim and VSCode Neovim integration.
- Imported from profiles/home/common.nix.
Plugins:
- tokyonight: colorscheme (night style)
- which-key: keybinding hints
- nvim-tree: file explorer (<leader>e)
- telescope: fuzzy finder (<leader>ff, <leader>fg, <leader>fb, <leader>fh)
- treesitter: syntax highlighting
- gitsigns: git integration
- lualine: status line
- indent-blankline: indent guides
- nvim-autopairs: auto pairs
- comment: commenting (gc, gb)
- nvim-surround: surround operations
- web-devicons: file icons
