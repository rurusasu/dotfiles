# AGENTS

Purpose: Home Manager module definitions (options only, no config).

## Structure

```
home/
  default.nix           # Imports all home modules
  terminals/            # Terminal emulator options (WezTerm, Windows Terminal)
    default.nix         # myHomeSettings.terminals options
  tmux/                 # Tmux options
    default.nix         # myHomeSettings.tmux options
  nixvim/               # Nixvim options
    default.nix         # myHomeSettings.nixvim options
```

## Design Pattern

- **Modules** define options only (in `nix/modules/`)
- **Profiles** provide configuration (in `nix/profiles/`)

This separation allows:
1. Options to be available across all hosts
2. Profiles to selectively enable features
3. Clear distinction between "what can be configured" vs "what is configured"

## Shared Settings Architecture

```
myHomeSettings
├── terminals              # Terminal emulators (WezTerm, Windows Terminal)
│   ├── leader.key         # Leader key (default: Space)
│   ├── leader.mods        # Modifiers (default: CTRL)
│   ├── leader.timeout     # Timeout in ms (default: 2000)
│   └── keybindings
│       ├── paneNavStyle   # vim or arrow
│       ├── paneZoom       # Pane zoom key (default: w)
│       └── tab            # Tab/window management (shared)
│           ├── new        # New tab key (default: t)
│           ├── close      # Close tab key (default: q)
│           ├── next       # Next tab key (default: n)
│           └── prev       # Previous tab key (default: p)
├── tmux                   # Tmux multiplexer
│   ├── enable             # Enable tmux
│   ├── prefix.key         # Prefix key (default: b)
│   ├── prefix.useTerminalsLeader  # Use terminals.leader
│   └── keybindings.paneNavStyle   # Inherits from terminals
└── nixvim                 # Neovim (Nixvim)
    ├── enable             # Enable nixvim
    ├── leader             # Vim leader (default: Space)
    ├── localLeader        # Local leader (default: \)
    ├── colorscheme.name   # Colorscheme (default: tokyonight)
    ├── colorscheme.style  # Style (default: night)
    └── features.*         # lsp, treesitter, telescope, git
```

## Keybinding Consistency

All tools share similar keybindings where possible:

| Action | WezTerm | Tmux | Neovim |
|--------|---------|------|--------|
| Leader key | CTRL+Space | C-b (or shared) | Space |
| Split horizontal | Leader+h | prefix+h | - |
| Split vertical | Leader+v | prefix+v | - |
| Close pane | Leader+x | prefix+x | - |
| Pane left | C-S-h | h | C-w h |
| Pane down | C-S-j | j | C-w j |
| Pane up | C-S-k | k | C-w k |
| Pane right | C-S-l | l | C-w l |
| New tab | Leader+t | prefix+t | Leader+t |
| Close tab | Leader+q | prefix+q | Leader+q |
| Next tab | Leader+n | prefix+n | Leader+n |
| Previous tab | Leader+p | prefix+p | Leader+p |
| Pane zoom | Leader+w | prefix+w | Leader+w |

## Usage

Modules are automatically imported via `nix/flakes/lib/shared-modules.nix`.

### Enable programs

```nix
# In profiles/home/default.nix or your user config
myHomeSettings = {
  nixvim.enable = true;
  tmux.enable = true;
  wezterm.enable = true;
};
```

### Customize settings

```nix
myHomeSettings = {
  # Change terminal leader key
  terminals.leader = {
    key = "a";
    mods = "CTRL";
  };

  # Tmux uses terminals.leader
  tmux.prefix.useTerminalsLeader = true;

  # Nixvim colorscheme
  nixvim.colorscheme = {
    name = "gruvbox";
    style = "dark";
  };
};
```

## Adding a New Module

1. Create `nix/modules/home/<name>/default.nix`
2. Define options with `mkOption`
3. Import in `nix/modules/home/default.nix`
4. Create profile in `nix/profiles/home/programs/<name>/`
