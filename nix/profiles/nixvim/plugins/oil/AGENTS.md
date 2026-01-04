# AGENTS

Purpose: oil.nvim file explorer - edit your filesystem like a buffer.

## Nixvim Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | false | Enable oil.nvim |
| `package` | package | pkgs.vimPlugins.oil-nvim | Oil package |
| `autoLoad` | bool | true | Auto load on startup |
| `settings` | attrs | {} | Options for `require('oil').setup` |
| `settings.delete_to_trash` | bool | false | Delete to trash instead of permanent |
| `settings.skip_confirm_for_simple_edits` | bool | false | Skip confirmation for simple edits |
| `settings.use_default_keymaps` | bool | true | Use default keymaps |
| `settings.view_options.show_hidden` | bool | false | Show hidden files |
| `settings.keymaps` | attrs | {} | Custom keymaps in oil buffer |
| `settings.columns` | list | ["icon"] | Columns to display |
| `settings.buf_options.buflisted` | bool | false | Show in buffer list |
| `settings.float.padding` | int | 2 | Floating window padding |
| `settings.float.max_width` | int | 0 | Max floating window width |
| `settings.float.max_height` | int | 0 | Max floating window height |

## Current Configuration

```nix
plugins.oil = {
  enable = true;
  package = pkgs.vimPlugins.oil-nvim;
  settings = {
    delete_to_trash = true;
    skip_confirm_for_simple_edits = true;
    use_default_keymaps = true;
    view_options.show_hidden = true;
    keymaps = {
      "g?" = "actions.show_help";
      "<CR>" = "actions.select";
      "<C-v>" = "actions.select_vsplit";
      # ... more keymaps
    };
  };
};
```

## Keymaps

### Global Keymap

| Key | Action | Description |
|-----|--------|-------------|
| `-` | `<cmd>Oil<cr>` | Open parent directory in Oil |

### Oil Buffer Keymaps

| Key | Action | Description |
|-----|--------|-------------|
| `g?` | show_help | Show help |
| `<CR>` | select | Open file/directory |
| `<C-v>` | select_vsplit | Open in vertical split |
| `<C-s>` | select_split | Open in horizontal split |
| `<C-t>` | select_tab | Open in new tab |
| `<C-p>` | preview | Preview file |
| `<C-c>` | close | Close oil |
| `<C-r>` | refresh | Refresh |
| `-` | parent | Go to parent directory |
| `_` | open_cwd | Open current working directory |
| `` ` `` | cd | Change directory |
| `~` | tcd | Tab-local cd |
| `gs` | change_sort | Change sort order |
| `gx` | open_external | Open with external program |
| `g.` | toggle_hidden | Toggle hidden files |

## Usage

1. Press `-` in normal mode to open Oil in parent directory
2. Navigate with j/k, Enter to open
3. Edit filenames directly in buffer to rename
4. Delete lines to delete files (goes to trash)
5. Save buffer to apply changes

## Sources

- [Nixvim Oil Docs](https://nix-community.github.io/nixvim/plugins/oil/index.html)
- [oil.nvim GitHub](https://github.com/stevearc/oil.nvim)
