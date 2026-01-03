# AGENTS

Purpose: fzf fuzzy finder module options.

## Home Manager `programs.fzf` Options

| Option | Type | Description |
|--------|------|-------------|
| `enable` | bool | Enable fzf |
| `package` | package | fzf package to use |
| `enableBashIntegration` | bool | Enable Bash integration |
| `enableFishIntegration` | bool | Enable Fish integration |
| `enableZshIntegration` | bool | Enable Zsh integration |
| `defaultCommand` | string | Default data source (`FZF_DEFAULT_COMMAND`) |
| `defaultOptions` | list of string | Default options (`FZF_DEFAULT_OPTS`) |
| `colors` | attrs | Color scheme settings |
| `fileWidgetCommand` | string | Data source for Ctrl+T |
| `fileWidgetOptions` | list of string | Options for Ctrl+T |
| `changeDirWidgetCommand` | string | Data source for Alt+C |
| `changeDirWidgetOptions` | list of string | Options for Alt+C |
| `historyWidgetOptions` | list of string | Options for Ctrl+R |
| `tmux` | attrs | tmux integration settings |

## Custom Module Options (`myHomeSettings.fzf`)

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | true | Enable fzf fuzzy finder |
| `searchRoot` | string | "/" | Root directory for file/directory search |
| `height` | string | "40%" | Height of fzf window |
| `layout` | enum | "reverse" | Layout: `default`, `reverse`, `reverse-list` |
| `border` | bool | true | Show border around fzf window |
| `prompt` | string | "> " | Prompt string |
| `extraOptions` | list of string | [] | Additional fzf default options |

## Search Root Directory

fzf does not have a built-in option for setting the search root directory.
The solution is to pass `. /` to fd commands:

```nix
defaultCommand = "${pkgs.fd}/bin/fd --type f . /";
fileWidgetCommand = "${pkgs.fd}/bin/fd --type f . /";
changeDirWidgetCommand = "${pkgs.fd}/bin/fd --type d . /";
```

The `myHomeSettings.fzf.searchRoot` option controls this behavior.

## Relationship with fd

The fzf profile automatically inherits all fd settings from `myHomeSettings.fd`:
- `hidden` → `--hidden`
- `followSymlinks` → `--follow`
- `noIgnoreVcs` → `--no-ignore-vcs`
- `maxResults` → `--max-results=N`
- `maxDepth` → `--max-depth=N`
- `extraOptions` → additional arguments

This ensures that fzf file/directory searches use the same fd configuration.

## Default Keybindings (zsh)

| Key | Action |
|-----|--------|
| Alt+Z | zoxide interactive (history-based directory jump) |
| Alt+D | fzf directory search and cd |
| Alt+T | fzf file/directory search and insert |
| Alt+R | fzf command history search |

Note: These replace the default fzf keybindings (Ctrl+T, Ctrl+R, Alt+C) to avoid WSL conflicts.

## Sources

- [MyNixOS programs.fzf options](https://mynixos.com/home-manager/options/programs.fzf)
- [Home Manager fzf.nix source](https://github.com/nix-community/home-manager/blob/master/modules/programs/fzf.nix)
