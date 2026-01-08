# AGENTS

Purpose: Home Manager module definitions (options only, no config).

## Structure

```
home/
  default.nix           # Imports all home modules
  fd/                   # fd file finder options
    default.nix         # myHomeSettings.fd options
  fzf/                  # fzf fuzzy finder options
    default.nix         # myHomeSettings.fzf options
  terminals/            # Terminal keybinding options (shared with tmux/WezTerm configs)
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
├── fd                     # fd file finder (used by fzf)
│   ├── enable             # Enable fd (default: true)
│   ├── hidden             # Search hidden files (default: true)
│   ├── followSymlinks     # Follow symlinks (default: true)
│   ├── noIgnoreVcs        # Ignore .gitignore (default: true)
│   ├── maxResults         # Max results (default: 1000)
│   ├── maxDepth           # Max depth (default: 5)
│   ├── ignores            # Paths to ignore (list)
│   └── extraOptions       # Additional fd options (list)
├── fzf                    # fzf fuzzy finder (uses fd settings)
│   ├── enable             # Enable fzf (default: true)
│   ├── searchRoot         # Search root directory (default: "/")
│   ├── height             # Window height (default: "40%")
│   ├── layout             # Layout: default/reverse/reverse-list (default: reverse)
│   ├── border             # Show border (default: true)
│   ├── prompt             # Prompt string (default: "> ")
│   └── extraOptions       # Additional fzf options (list)
├── terminals              # Terminal emulators (WezTerm, Windows Terminal)
│   ├── leader.key         # Leader key (default: Space)
│   ├── leader.mods        # Modifiers (default: CTRL)
│   ├── leader.timeout     # Timeout in ms (default: 2000)
│   └── keybindings
│       ├── paneNavStyle   # vim or arrow
│       ├── paneZoom       # Pane zoom key (default: w)
│       └── tab            # Tab/window management (shared)
│           ├── new        # New tab key (default: t)
│           ├── close      # Close tab key (default: x)
│           ├── next       # Next tab key (default: l)
│           └── prev       # Previous tab key (default: h)
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

### Tab Operations (Leader-based)

| Action | WezTerm | Tmux | Neovim |
|--------|---------|------|--------|
| Leader key | CTRL+Space | C-b (or shared) | Space |
| New tab | Leader+t | prefix+t | Leader+t |
| Close tab | Leader+x | prefix+x | Leader+x |
| Next tab | Leader+l | prefix+l | Leader+l |
| Previous tab | Leader+h | prefix+h | Leader+h |
| Tab 1-9 | Leader+1-9 | prefix+1-9 | - |

### Pane Operations (Ctrl+Alt in WezTerm)

| Action | WezTerm | Tmux | Neovim |
|--------|---------|------|--------|
| Split horizontal | C-A-h | prefix+h | - |
| Split vertical | C-A-v | prefix+v | - |
| Close pane | C-A-x | prefix+x | - |
| Pane zoom | C-A-w | prefix+w | Leader+w |
| Resize left | C-A-Left | prefix+H | - |
| Resize down | C-A-Down | prefix+J | - |
| Resize up | C-A-Up | prefix+K | - |
| Resize right | C-A-Right | prefix+L | - |

### Pane Navigation (Ctrl+Shift in WezTerm)

| Action | WezTerm | Tmux | Neovim |
|--------|---------|------|--------|
| Pane left | C-S-h | h | C-w h |
| Pane down | C-S-j | j | C-w j |
| Pane up | C-S-k | k | C-w k |
| Pane right | C-S-l | l | C-w l |

## Usage

Modules are automatically imported via `nix/flakes/lib/shared-modules.nix`.

### Enable programs

```nix
# In profiles/home/default.nix or your user config
myHomeSettings = {
  nixvim.enable = true;
  tmux.enable = true;
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

  # Terminal configs are managed by chezmoi (edit there directly)

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
