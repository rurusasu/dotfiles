# Chezmoi Home Manager Module

## Overview

Nix module for chezmoi dotfile management with 1Password SSH agent integration.

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `programs.chezmoi.enable` | bool | false | Enable chezmoi |
| `programs.chezmoi.package` | package | pkgs.chezmoi | Chezmoi package |
| `programs.chezmoi.sourceDir` | string | ~/.local/share/chezmoi | Source directory |
| `programs.chezmoi.onePassword.enable` | bool | false | Enable 1Password SSH agent |
| `programs.chezmoi.onePassword.agentPath` | string | (OS-dependent) | Agent socket path |

## Usage

```nix
{
  programs.chezmoi = {
    enable = true;
    onePassword.enable = true;
  };
}
```

## 1Password Agent Paths

- **macOS**: `~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock`
- **Linux/WSL**: `~/.1password/agent.sock` (symlinked from Windows)

## Files

- `default.nix` - Module implementation
