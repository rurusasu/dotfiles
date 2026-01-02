{ ... }:
{
  programs.zsh = {
    enable = true;
    shellAliases = {
      nrs = "sudo nixos-rebuild switch --flake ~/.dotfiles --impure";
      nrt = "sudo nixos-rebuild test --flake ~/.dotfiles --impure";
      nrb = "sudo nixos-rebuild boot --flake ~/.dotfiles --impure";
    };
  };
}
