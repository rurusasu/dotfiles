# AGENTS

Purpose: WezTerm keybinding configuration module.

## Structure

Keybindings are defined as Nix attribute sets and converted to Lua.

```nix
keybindings = {
  pane = [ ... ];      # Pane management (split, close)
  paneNav = [ ... ];   # Pane navigation (Vim-like hjkl)
  paneResize = [ ... ]; # Pane resize (arrow keys)
  tab = [ ... ];       # Tab management
  misc = [ ... ];      # Copy mode, quick select
  font = [ ... ];      # Font size controls
};
```

## Keybinding Format

```nix
{ key = "h"; mods = "LEADER"; action = ''act.SplitHorizontal(...)''; }
```

| Field | Description |
|-------|-------------|
| `key` | Key name (e.g., "h", "Tab", "LeftArrow") |
| `mods` | Modifiers (e.g., "LEADER", "CTRL\|SHIFT") |
| `action` | Lua action string (uses `act.*` functions) |

## Exports

| Name | Description |
|------|-------------|
| `keybindingsLua` | Generated Lua code for `config.keys` |
| `leaderLua` | Generated Lua code for leader key config |
| `keybindings` | Raw Nix keybinding definitions (for external use) |

## Auto-generated Keybindings

Tab number keybindings (Leader + 1-9) are generated using `builtins.genList`.

## References

- [WezTerm key binding docs](https://wezfurlong.org/wezterm/config/keys.html)
- [WezTerm key actions](https://wezfurlong.org/wezterm/config/lua/keyassignment/index.html)
