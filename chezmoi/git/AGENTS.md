# Git Configuration

Git configuration with SSH signing and cross-platform support.

## Files

| File | Deployed To | Description |
|------|-------------|-------------|
| `gitconfig.tmpl` | `~/.gitconfig` | Git configuration (chezmoi template) |

## Features

- **User**: Configured with name and email
- **SSH Signing**: Commits are signed with SSH key
- **Credential Helper**: SSH-based (GitHub/Gist)
- **Editor**: nvim as default
- **Safe Directories**: Configured for cross-platform use

## Template Variables

The `.tmpl` extension indicates this is a chezmoi template. Variables:
- Platform-specific settings can be added using chezmoi template syntax

## Related

- SSH keys should be managed separately (not in this repository)
- GitHub CLI (`gh`) authentication is separate
