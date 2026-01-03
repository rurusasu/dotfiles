# AGENTS

Purpose: Gitsigns git integration and decorations.

## Nixvim Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | false | Enable gitsigns |
| `package` | package | pkgs.vimPlugins.gitsigns-nvim | Gitsigns package |
| `autoLoad` | bool | true | Auto load on startup |
| `settings` | attrs | {} | Options for `require('gitsigns').setup` |
| `settings.signs` | attrs | {} | Sign column symbols |
| `settings.signs.add.text` | string | "+" | Added line symbol |
| `settings.signs.change.text` | string | "~" | Changed line symbol |
| `settings.signs.delete.text` | string | "_" | Deleted line symbol |
| `settings.current_line_blame` | bool | false | Show blame on current line |
| `settings.current_line_blame_opts` | attrs | {} | Blame options |
| `settings.sign_priority` | int | 6 | Sign priority |
| `settings.attach_to_untracked` | bool | true | Attach to untracked files |

## Current Configuration

```nix
plugins.gitsigns = {
  enable = true;
  package = pkgs.vimPlugins.gitsigns-nvim;
};
```

## Conditional Activation

This plugin is conditionally enabled based on `myHomeSettings.nixvim.features.git`.

## Sources

- [Nixvim Gitsigns Docs](https://nix-community.github.io/nixvim/plugins/gitsigns/index.html)
- [Gitsigns Settings](https://nix-community.github.io/nixvim/plugins/gitsigns/settings/index.html)
- [gitsigns.nvim GitHub](https://github.com/lewis6991/gitsigns.nvim)
