# AGENTS

Purpose: nvim-tree file explorer configuration.

## Nixvim Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | false | Enable nvim-tree |
| `package` | package | pkgs.vimPlugins.nvim-tree-lua | nvim-tree package |
| `autoLoad` | bool | true | Auto load on startup |
| `settings` | attrs | {} | Options for `require('nvim-tree').setup` |
| `settings.filters.dotfiles` | bool | false | Hide dotfiles |
| `settings.filters.custom` | list | [] | Custom filter patterns |
| `settings.view.width` | int | 30 | Window width |
| `settings.view.side` | string | "left" | Window side |
| `settings.renderer.icons.show.file` | bool | true | Show file icons |
| `settings.renderer.icons.show.folder` | bool | true | Show folder icons |
| `settings.git.enable` | bool | true | Enable git integration |
| `settings.update_focused_file.enable` | bool | false | Update focused file |

## Current Configuration

```nix
plugins.nvim-tree = {
  enable = true;
  package = pkgs.vimPlugins.nvim-tree-lua;
  settings.filters.dotfiles = false;
};
```

## Keymaps (defined in main config)

| Key | Action | Description |
|-----|--------|-------------|
| `<leader>e` | `NvimTreeToggle` | Toggle file explorer |

## Sources

- [Nixvim nvim-tree Docs](https://nix-community.github.io/nixvim/plugins/nvim-tree/index.html)
- [nvim-tree.lua GitHub](https://github.com/nvim-tree/nvim-tree.lua)
