# AGENTS

Purpose: fd file finder module options.

## Home Manager `programs.fd` Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | false | Enable fd |
| `package` | package | pkgs.fd | fd package to use |
| `hidden` | bool | false | Search hidden files (`--hidden`) |
| `ignores` | list of string | [] | Paths to ignore (written to `~/.config/fd/ignore`) |
| `extraOptions` | list of string | [] | Additional arguments (`--follow`, etc.) |

## Custom Module Options (`myHomeSettings.fd`)

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | true | Enable fd file finder |
| `hidden` | bool | true | Search hidden files and directories |
| `followSymlinks` | bool | true | Follow symbolic links (`--follow`) |
| `noIgnoreVcs` | bool | true | Do not respect .gitignore (`--no-ignore-vcs`) |
| `maxResults` | int or null | 1000 | Maximum number of search results |
| `maxDepth` | int or null | 5 | Maximum search depth |
| `ignores` | list of string | (see below) | Paths to ignore globally |
| `extraOptions` | list of string | [] | Additional fd options |

### Default Ignores

```nix
[
  ".git/"
  "node_modules/"
  "target/"
  "__pycache__/"
  ".cache/"
  ".nix-profile/"
  ".local/share/"
  ".npm/"
  ".cargo/"
]
```

## Relationship with fzf

The fd module settings are automatically used by:
- `programs.fzf.defaultCommand`
- `programs.fzf.fileWidgetCommand`
- `programs.fzf.changeDirWidgetCommand`
- zsh custom widgets (Alt+D, Alt+T)

This ensures consistent behavior across all fuzzy finding operations.

## Sources

- [Home Manager fd.nix source](https://github.com/nix-community/home-manager/blob/master/modules/programs/fd.nix)
