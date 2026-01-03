# AGENTS

Purpose: Home Manager tmux configuration.

## Structure

```
tmux/
  default.nix   # Tmux configuration (uses mkIf cfg.enable)
```

## Options Location

Options are defined in `nix/modules/home/tmux/default.nix`.

## Shared Settings

Tmux can share keybindings with terminal emulators:

```nix
myHomeSettings.tmux = {
  enable = true;
  prefix.useTerminalsLeader = true;  # Use terminals.leader for prefix
};
```

When `useTerminalsLeader = true`, the tmux prefix becomes the same as the terminal leader key (e.g., `CTRL+Space` becomes `C-space`).

## Options

| Option | Default | Description |
|--------|---------|-------------|
| `enable` | `false` | Enable tmux |
| `prefix.key` | `b` | Prefix key (for C-b) |
| `prefix.useTerminalsLeader` | `false` | Use terminals.leader |
| `keybindings.paneNavStyle` | (from terminals) | vim or arrow |

## Keybindings

| Action | Keybinding |
|--------|------------|
| Split horizontal | prefix + h |
| Split vertical | prefix + v |
| Close pane | prefix + x |
| Navigate (vim) | h/j/k/l |
| Navigate (arrow) | Arrow keys |
| Resize | H/J/K/L (repeat) |

See `nix/modules/home/AGENTS.md` for full shared settings architecture.
