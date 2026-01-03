# AGENTS

Purpose: indent-blankline indentation guides configuration.

## Nixvim Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | false | Enable indent-blankline |
| `package` | package | pkgs.vimPlugins.indent-blankline-nvim | Package |
| `autoLoad` | bool | true | Auto load on startup |
| `settings` | attrs | {} | Options for `require('ibl').setup` |
| `settings.indent.char` | string | "│" | Indent guide character |
| `settings.indent.highlight` | string/list | nil | Highlight group(s) |
| `settings.indent.priority` | int | 1 | Virtual text priority |
| `settings.whitespace.remove_blankline_trail` | bool | true | Remove trailing whitespace |
| `settings.scope.enabled` | bool | true | Enable scope highlighting |
| `settings.scope.show_start` | bool | true | Show scope start |
| `settings.scope.show_end` | bool | false | Show scope end |

## Current Configuration

```nix
plugins.indent-blankline = {
  enable = true;
  package = pkgs.vimPlugins.indent-blankline-nvim;
};
```

## Notes

- Scope requires treesitter to be set up
- Scope refers to variable/function accessibility scope
- Character display width must be 0 or 1

## Sources

- [Nixvim indent-blankline Docs](https://nix-community.github.io/nixvim/plugins/indent-blankline/index.html)
- [Indent Settings](https://nix-community.github.io/nixvim/plugins/indent-blankline/settings/indent.html)
- [indent-blankline.nvim GitHub](https://github.com/lukas-reineke/indent-blankline.nvim)
