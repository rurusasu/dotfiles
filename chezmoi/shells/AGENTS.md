# Shell Configurations

Shell configuration files for bash, zsh, PowerShell, and POSIX profile.

## Documentation

- [Keybinding Policy](../../docs/chezmoi/keybindings.md)

## Files

| File                               | Deployed To                                                      | Description                    |
| ---------------------------------- | ---------------------------------------------------------------- | ------------------------------ |
| `bashrc`                           | `~/.bashrc`                                                      | Bash shell configuration       |
| `zshrc`                            | `~/.zshrc`                                                       | Zsh shell configuration        |
| `profile`                          | `~/.profile`                                                     | POSIX profile (login shell)    |
| `Microsoft.PowerShell_profile.ps1` | `~/Documents/PowerShell/Microsoft.PowerShell_profile.ps1`        | PowerShell 7 profile           |
| `Microsoft.PowerShell_profile.ps1` | `~/Documents/WindowsPowerShell/Microsoft.PowerShell_profile.ps1` | Windows PowerShell 5.1 profile |

## Features

### Common Features (both bash/zsh)

- Aliases: `grep` → `rg`, `find` → `fd`
- PATH additions: `~/bin`, `~/.local/bin`
- Tool integrations: starship, zoxide, fzf
- NVM (Node Version Manager) support

### Zsh-specific

- Kubernetes aliases (k, kgn, kgp, kgs)
- NixOS rebuild aliases (nrs, nrt, nrb)

### Interactive keybindings (bash/zsh/powershell)

- zoxide jump: `Alt+Z`
- fzf directory search: `Alt+D`
- fzf file insert: `Alt+T`
- fzf history search: `Alt+R`

## Shell Integration

- zsh/bash: integrations are primarily managed via shell files in this directory
- PowerShell: integrations are managed by `Microsoft.PowerShell_profile.ps1`

These files provide:

- Environment variables
- Aliases
- Custom functions / key handlers

## 1Password Secret Integration

各シェル設定の末尾で `~/.config/shell/secret.sh` (または `.ps1`) を source する:

```bash
# .bashrc / .zshrc
[[ -f "$HOME/.config/shell/secret.sh" ]] && source "$HOME/.config/shell/secret.sh"
```

```powershell
# Microsoft.PowerShell_profile.ps1
$_secretPs1 = Join-Path $HOME ".config\shell\secret.ps1"
if (Test-Path $_secretPs1) { . $_secretPs1 }
```

- secret ファイルは `chezmoi/secret/` で管理・deploy scripts 経由で配置される
- `op` が PATH にない環境では自動スキップ (Git Bash / WSL / Windows 全対応)

## Platform Notes

- **Windows**: These files are deployed but typically used in WSL/Git Bash
- **Linux/WSL**: Primary target platform
- **DevContainer**: Used for development containers
