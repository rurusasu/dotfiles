{
  pkgs,
  lib,
  inputs,
  ...
}:
let
  sets = import ../packages/sets.nix {
    inherit pkgs lib;
  };
in
{
  imports = [
    ./common.nix
    ./hermes-agent.nix
  ];

  home.packages = sets.all;

  programs.zsh.shellAliases = {
    nrs = "~/.dotfiles/install.sh";
  };
}
