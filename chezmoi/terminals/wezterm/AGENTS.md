# WezTerm Configuration

WezTerm is a GPU-accelerated cross-platform terminal emulator.

## Files

| File | Deployed To |
|------|-------------|
| `wezterm.lua` | `~/.config/wezterm/wezterm.lua` |

## Configuration

### Appearance
- **Color scheme**: Gruvbox Dark (custom)
- **Font**: Consolas, 12pt
- **Opacity**: 85%
- **Window decorations**: Resize only

### Features
- IME support enabled
- Tab bar (hidden when single tab)
- Fancy tab bar disabled

### Platform Detection

Uses Lua-based OS detection:
```lua
local is_windows = wezterm.target_triple:find("windows") ~= nil
if is_windows then
  config.default_prog = { "pwsh.exe", "-NoLogo" }
end
```

## Keybindings

### Leader Key: `Ctrl+Space`
| Key | Action |
|-----|--------|
| `Leader + T` | New tab |
| `Leader + X` | Close tab |
| `Leader + H` | Previous tab |
| `Leader + L` | Next tab |
| `Leader + 1-9` | Go to tab N |
| `Leader + [` | Copy mode |
| `Leader + Space` | Quick select |

### Pane Operations
| Key | Action |
|-----|--------|
| `Ctrl+Alt+H` | Split horizontal |
| `Ctrl+Alt+V` | Split vertical |
| `Ctrl+Alt+X` | Close pane |
| `Ctrl+Alt+W` | Toggle zoom |

### Pane Navigation
| Key | Action |
|-----|--------|
| `Ctrl+Shift+H` | Focus left |
| `Ctrl+Shift+J` | Focus down |
| `Ctrl+Shift+K` | Focus up |
| `Ctrl+Shift+L` | Focus right |

### Other
| Key | Action |
|-----|--------|
| `F11` | Toggle fullscreen |
| `Ctrl+/-/0` | Font size |

## Installation

- **Linux/WSL**: `nix` (home.packages)
- **Windows**: `winget install wez.wezterm`

## Customization

Edit `wezterm.lua`. Configuration uses Lua with hot-reload support.
