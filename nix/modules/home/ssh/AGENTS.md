# SSH Home Manager Module

## Overview

OS-independent SSH configuration with 1Password SSH agent integration.

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `modules.ssh.enable` | bool | false | Enable SSH configuration |
| `modules.ssh.onePassword.enable` | bool | false | Enable 1Password agent |
| `modules.ssh.onePassword.agentPath` | string | (OS-dependent) | Agent socket path |
| `modules.ssh.githubHosts` | attrset | {} | GitHub host configurations |

## Usage

```nix
{
  modules.ssh = {
    enable = true;
    onePassword.enable = true;

    githubHosts = {
      "github.com-personal" = {
        identityFile = "~/.ssh/personal_key.pub";
      };
      "github.com" = {
        identityFile = "~/.ssh/signing_key.pub";
      };
    };
  };
}
```

## OS-Specific Agent Paths

| OS | Default Path |
|----|--------------|
| macOS | `~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock` |
| Linux/WSL | `~/.1password/agent.sock` |
| Windows | `//./pipe/openssh-ssh-agent` (handled by chezmoi) |

## Files

- `default.nix` - Module implementation
