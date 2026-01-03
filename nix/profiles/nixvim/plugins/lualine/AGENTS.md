# AGENTS

Purpose: Lualine status line configuration.

## Nixvim Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | false | Enable lualine |
| `package` | package | pkgs.vimPlugins.lualine-nvim | Lualine package |
| `autoLoad` | bool | true | Auto load on startup |
| `settings.options.theme` | string | "auto" | Colorscheme theme |
| `settings.options.globalstatus` | bool | false | Single statusline |
| `settings.options.icons_enabled` | bool | true | Show icons |
| `settings.options.component_separators` | attrs | {} | Component separators |
| `settings.options.section_separators` | attrs | {} | Section separators |
| `settings.sections` | attrs | {} | Configure lualine_a through lualine_z |
| `settings.inactive_sections` | attrs | {} | Inactive window sections |

## Lualine Sections Layout

```
+-------------------------------------------------+
| A | B | C                            X | Y | Z |
+-------------------------------------------------+
```

## Current Configuration

```nix
plugins.lualine = {
  enable = true;
  package = pkgs.vimPlugins.lualine-nvim;
  settings.options.theme = cfg.colorscheme.name;
};
```

## Common Section Components

- `mode` - Current mode
- `branch` - Git branch
- `filename` - File name
- `diff` - Git diff
- `diagnostics` - LSP diagnostics
- `encoding` - File encoding
- `filetype` - File type
- `progress` - File progress
- `location` - Cursor location

## Sources

- [Nixvim Lualine Docs](https://nix-community.github.io/nixvim/plugins/lualine/index.html)
- [Lualine Settings](https://nix-community.github.io/nixvim/plugins/lualine/settings/index.html)
- [lualine.nvim GitHub](https://github.com/nvim-lualine/lualine.nvim)
