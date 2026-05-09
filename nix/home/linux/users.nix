# User → Home Manager module mapping for native Linux host.
# Imported by nix/flakes/hosts.nix as home-manager.users.
{
  nixos =
    { ... }:
    {
      imports = [ ../common.nix ];

      # NixOS rebuild shortcuts (also defined in wsl/users.nix for WSL context)
      programs.zsh.shellAliases = {
        nrs = "sudo nixos-rebuild switch --flake ~/.dotfiles --impure && nix profile upgrade '.*' || nix profile install ~/.dotfiles#default";
        nrt = "sudo nixos-rebuild test --flake ~/.dotfiles --impure";
        nrb = "sudo nixos-rebuild boot --flake ~/.dotfiles --impure";
      };
    };
}
