# SSH Configuration

## Overview

OS-independent SSH configuration with 1Password SSH Agent integration.

## Files

- `config.tmpl` - SSH config template with OS-specific 1Password agent paths

## 1Password SSH Agent Paths

| OS | Agent Path |
|----|------------|
| Windows | `//./pipe/openssh-ssh-agent` |
| macOS | `~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock` |
| Linux/WSL | `~/.1password/agent.sock` |

## GitHub Hosts

- `github.com-personal` - Personal account (rurusasu)
- `github.com` - Work account (default)

## Requirements

1. 1Password desktop app with SSH Agent enabled
2. SSH keys stored in 1Password with "Use for SSH" enabled
3. Public keys exported to `~/.ssh/` (referenced by IdentityFile)
