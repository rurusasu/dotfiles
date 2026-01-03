# AGENTS

Purpose: Comment.nvim code commenting configuration.

## Nixvim Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | false | Enable comment |
| `package` | package | pkgs.vimPlugins.comment-nvim | Package |
| `autoLoad` | bool | true | Auto load on startup |
| `settings` | attrs | {} | Options for `require('Comment').setup` |
| `settings.padding` | bool | true | Add space after comment |
| `settings.sticky` | bool | true | Cursor stays in place |
| `settings.ignore` | string | nil | Ignore pattern (regex) |
| `settings.toggler.line` | string | "gcc" | Line comment toggle |
| `settings.toggler.block` | string | "gbc" | Block comment toggle |
| `settings.opleader.line` | string | "gc" | Line comment operator |
| `settings.opleader.block` | string | "gb" | Block comment operator |
| `settings.extra.above` | string | "gcO" | Add comment above |
| `settings.extra.below` | string | "gco" | Add comment below |
| `settings.extra.eol` | string | "gcA" | Add comment at end of line |

## Current Configuration

```nix
plugins.comment = {
  enable = true;
  package = pkgs.vimPlugins.comment-nvim;
};
```

## Default Keybindings

| Key | Mode | Action |
|-----|------|--------|
| `gcc` | Normal | Toggle line comment |
| `gbc` | Normal | Toggle block comment |
| `gc{motion}` | Normal | Comment with motion |
| `gc` | Visual | Comment selection |
| `gcO` | Normal | Add comment above |
| `gco` | Normal | Add comment below |
| `gcA` | Normal | Add comment at EOL |

## Sources

- [Nixvim Comment Docs](https://nix-community.github.io/nixvim/plugins/comment/index.html)
- [Comment.nvim GitHub](https://github.com/numToStr/Comment.nvim)
