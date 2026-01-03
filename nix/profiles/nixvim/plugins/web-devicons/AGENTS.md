# AGENTS

Purpose: nvim-web-devicons file type icons configuration.

## Nixvim Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | false | Enable web-devicons |
| `package` | package | pkgs.vimPlugins.nvim-web-devicons | Package |
| `autoLoad` | bool | true | Auto load on startup |
| `settings` | attrs | {} | Options for `require('nvim-web-devicons').setup` |
| `settings.strict` | bool | false | Strict icon matching |
| `settings.color_icons` | bool | true | Enable colored icons |
| `settings.default` | bool | false | Show default icon |
| `override` | attrs | {} | Custom icon overrides |
| `override_by_filename` | attrs | {} | Override by filename |
| `override_by_extension` | attrs | {} | Override by extension |

## Current Configuration

```nix
plugins.web-devicons = {
  enable = true;
  package = pkgs.vimPlugins.nvim-web-devicons;
  settings.strict = true;
};
```

## Requirements

- Requires Nerd Fonts version 2.3 or above
- Nerd Fonts v3.0 moved some symbols
- Version 2.3 supports both v2 and v3 icons

## Used By

This plugin provides icons for:
- nvim-tree (file explorer)
- telescope (fuzzy finder)
- lualine (status line)
- bufferline (buffer tabs)

## Sources

- [Nixvim web-devicons Docs](https://nix-community.github.io/nixvim/plugins/web-devicons/index.html)
- [nvim-web-devicons GitHub](https://github.com/nvim-tree/nvim-web-devicons)
