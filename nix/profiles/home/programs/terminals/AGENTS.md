# AGENTS

Purpose: Terminal emulator configurations with shared settings.

## Structure

```
terminals/
  default.nix       # Profile config (enables terminals)
  keybindings.nix   # Shared keybindings for all terminals
  wezterm/          # WezTerm configuration
  windows-terminal/ # Windows Terminal configuration
```

## Options Location

Options are defined in `nix/modules/home/terminals/default.nix`.

## Relation to Other Tools

The `terminals.leader` and `terminals.keybindings` settings can be shared with:

- **tmux**: Set `myHomeSettings.tmux.prefix.useTerminalsLeader = true`
- **Neovim**: Uses its own leader (Space by default), but pane navigation is similar

See `nix/modules/home/AGENTS.md` for the full shared settings architecture.

## Shared Options

Defined in `myHomeSettings.terminals`:

| Option | Default | Description |
|--------|---------|-------------|
| `leader.key` | `Space` | Leader key for WezTerm |
| `leader.mods` | `CTRL` | Leader key modifiers |
| `leader.timeout` | `2000` | Leader timeout (ms) |
| `keybindings.paneNavStyle` | `vim` | Navigation style (vim/arrow) |

## Keybindings

Keybindings are defined in `keybindings.nix` and shared between terminals.

| Action | WezTerm | Windows Terminal | Tmux (shared) |
|--------|---------|------------------|---------------|
| Split horizontal | Leader+h | Ctrl+Shift+H | prefix+h |
| Split vertical | Leader+v | Ctrl+Shift+V | prefix+v |
| Close pane | Leader+x | Ctrl+Shift+X | prefix+x |
| Move left | Ctrl+Shift+H | Ctrl+Alt+H | h |
| Move down | Ctrl+Shift+J | Ctrl+Alt+J | j |
| Move up | Ctrl+Shift+K | Ctrl+Alt+K | k |
| Move right | Ctrl+Shift+L | Ctrl+Alt+L | l |

Note: Windows Terminal doesn't support Leader key natively.

## Customization

Change leader key in your configuration:

```nix
myHomeSettings.terminals.leader = {
  key = "a";
  mods = "CTRL";
};

# Also apply to tmux
myHomeSettings.tmux.prefix.useTerminalsLeader = true;
```
