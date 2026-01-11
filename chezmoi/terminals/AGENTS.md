# Terminal Configurations

Terminal emulator configurations for cross-platform use.

## Terminals

| Terminal | Config Path | Platform |
|----------|-------------|----------|
| WezTerm | `wezterm/wezterm.lua` | All (Windows, Linux, macOS) |
| Windows Terminal | `windows-terminal/settings.json` | Windows only |

## Deployment Paths

| Terminal | Windows | Linux/WSL |
|----------|---------|-----------|
| WezTerm | `~/.config/wezterm/` | `~/.config/wezterm/` |
| Windows Terminal | `%LOCALAPPDATA%/Packages/Microsoft.WindowsTerminal.../LocalState/` | N/A |

## Shared Configuration

### Common Settings
- **Font**: Consolas, 12pt
- **Opacity**: 85%
- **Color Scheme**: Gruvbox Dark

### Unified Keybindings
Both terminals share consistent keybindings:

| Action | Key |
|--------|-----|
| Split horizontal | `Ctrl+Alt+H` |
| Split vertical | `Ctrl+Alt+V` |
| Close pane | `Ctrl+Alt+X` |
| Toggle zoom | `Ctrl+Alt+W` |
| Navigate left | `Ctrl+Shift+H` |
| Navigate down | `Ctrl+Shift+J` |
| Navigate up | `Ctrl+Shift+K` |
| Navigate right | `Ctrl+Shift+L` |
| Fullscreen | `F11` |

### WezTerm Leader Key
WezTerm uses `Ctrl+Space` as leader key for additional bindings:
- `Leader + T`: New tab
- `Leader + X`: Close tab
- `Leader + H/L`: Previous/Next tab
- `Leader + 1-9`: Switch to tab N
- `Leader + [`: Copy mode
- `Leader + Space`: Quick select

## Platform Detection

WezTerm uses Lua-based OS detection (recommended approach):
```lua
if wezterm.target_triple:find("windows") then
  -- Windows settings
else
  -- Linux/macOS settings
end
```

## Installation

- **Linux/WSL**: Nix (`home.packages = [ wezterm ]`)
- **Windows**: winget (`winget install wez.wezterm`)
