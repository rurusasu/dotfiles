# AGENTS

Purpose: nvim-autopairs automatic bracket pairing configuration.

## Nixvim Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | false | Enable nvim-autopairs |
| `package` | package | pkgs.vimPlugins.nvim-autopairs | Package |
| `autoLoad` | bool | true | Auto load on startup |
| `settings` | attrs | {} | Options for `require('nvim-autopairs').setup` |
| `settings.check_ts` | bool | false | Use treesitter for pair checking |
| `settings.disable_filetype` | list | ["TelescopePrompt"] | Disabled filetypes |
| `settings.enable_moveright` | bool | true | Enable move right |
| `settings.enable_afterquote` | bool | true | Enable after quote |
| `settings.enable_check_bracket_line` | bool | true | Check bracket in same line |
| `settings.map_bs` | bool | true | Map backspace to delete pair |
| `settings.map_c_h` | bool | false | Map C-h to delete pair |
| `settings.map_c_w` | bool | false | Map C-w to delete pair |
| `settings.map_cr` | bool | true | Map CR for completion |
| `settings.disable_in_macro` | bool | true | Disable in macro recording |
| `settings.disable_in_replace_mode` | bool | true | Disable in replace mode |

## Current Configuration

```nix
plugins.nvim-autopairs = {
  enable = true;
  package = pkgs.vimPlugins.nvim-autopairs;
  settings = {
    check_ts = true;
    disable_filetype = [ "TelescopePrompt" ];
  };
};
```

## Sources

- [Nixvim nvim-autopairs Docs](https://nix-community.github.io/nixvim/plugins/nvim-autopairs/index.html)
- [nvim-autopairs Settings](https://nix-community.github.io/nixvim/plugins/nvim-autopairs/settings/index.html)
- [nvim-autopairs GitHub](https://github.com/windwp/nvim-autopairs)
