# AGENTS

Purpose: nvim-surround text surrounding manipulation configuration.

## Nixvim Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | false | Enable nvim-surround |
| `package` | package | pkgs.vimPlugins.nvim-surround | Package |
| `autoLoad` | bool | true | Auto load on startup |
| `settings` | attrs | {} | Options for `require('nvim-surround').setup` |
| `settings.keymaps.insert` | string | "<C-g>s" | Insert mode keymap |
| `settings.keymaps.insert_line` | string | "<C-g>S" | Insert line keymap |
| `settings.keymaps.normal` | string | "ys" | Normal mode add |
| `settings.keymaps.normal_cur` | string | "yss" | Normal mode add current line |
| `settings.keymaps.normal_line` | string | "yS" | Normal mode add on new lines |
| `settings.keymaps.visual` | string | "S" | Visual mode add |
| `settings.keymaps.delete` | string | "ds" | Delete surrounding |
| `settings.keymaps.change` | string | "cs" | Change surrounding |

## Current Configuration

```nix
plugins.nvim-surround = {
  enable = true;
  package = pkgs.vimPlugins.nvim-surround;
};
```

## Usage Examples

| Command | Action |
|---------|--------|
| `ysiw"` | Surround word with quotes |
| `ds"` | Delete surrounding quotes |
| `cs"'` | Change " to ' |
| `yss)` | Surround line with parentheses |
| `S"` (visual) | Surround selection with quotes |

## Sources

- [Nixvim nvim-surround Docs](https://nix-community.github.io/nixvim/plugins/nvim-surround/index.html)
- [nvim-surround GitHub](https://github.com/kylechui/nvim-surround)
