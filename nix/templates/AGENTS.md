# AGENTS

Purpose: Nix flake templates for project development environments.
Expected contents:
- python/: Python development environment template (flake.nix, .envrc).

## Usage

```bash
# Initialize a new project with template
nix flake init --template github:YOUR_USER/dotfiles#python

# Enable direnv
direnv allow
```

## Team Setup

1. Install Nix: `curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install`
2. Add to shell: `echo 'eval "$(direnv hook bash)"' >> ~/.bashrc`
3. Clone project and run `direnv allow`

## References

- [nix-direnv](https://github.com/nix-community/nix-direnv)
- [dev-templates](https://github.com/the-nix-way/dev-templates)
- [Determinate Systems Nix Installer](https://determinate.systems/posts/determinate-nix-installer)
- [devenv with Flakes](https://devenv.sh/guides/using-with-flakes/)
- [NixOS & Flakes Book - Dev Environments](https://nixos-and-flakes.thiscute.world/development/dev-environments)

