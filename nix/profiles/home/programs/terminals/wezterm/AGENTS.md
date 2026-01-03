# AGENTS

Purpose: WezTerm Home Manager module with custom options.

## Directory Structure
```
wezterm/
├── default.nix       # Main module (options + config)
└── keybind/
    └── default.nix   # Keybindings configuration
```

## Module Options

Enable via `myHomeSettings.wezterm.enable = true;`

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | false | Enable WezTerm |
| `font.family` | str | "Consolas" | Font family |
| `font.size` | float | 12.0 | Font size |
| `window.opacity` | float | 0.85 | Window opacity |
| `window.decorations` | str | "RESIZE" | Window decorations |
| `window.padding.{left,right,top,bottom}` | int | 8,8,6,6 | Padding |
| `leader.key` | str | "q" | Leader key |
| `leader.mods` | str | "CTRL" | Leader modifiers |
| `leader.timeout` | int | 2000 | Leader timeout (ms) |

## Color Scheme

Uses `programs.wezterm.colorSchemes` (Nix native) instead of Lua.
Base16-style Gruvbox Dark palette defined in `colors` attribute set.

## References

- [Home Manager WezTerm options](https://mynixos.com/home-manager/options/programs.wezterm)
- [WezTerm configuration docs](https://wezfurlong.org/wezterm/config/files.html)
- [home-manager wezterm.nix source](https://github.com/nix-community/home-manager/blob/master/modules/programs/wezterm.nix)
