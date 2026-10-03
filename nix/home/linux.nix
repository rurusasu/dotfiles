{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
let
  sets = import ../packages/sets.nix {
    inherit pkgs lib;
  };
  fonts = (import ../modules/fonts.nix { inherit pkgs; }).fonts;
in
{
  home.homeDirectory = lib.mkDefault "/home/${config.home.username}";

  imports = [
    ./nixos.nix
    ./common.nix
    ./hermes-agent.nix
  ];

  home.packages = sets.allWithout (sets.nativeDesktopPackageNames ++ [ "neovim" ]) ++ fonts.packages;
  fonts.fontconfig = fonts.fontconfig;

  programs.zsh.shellAliases = {
    nrs = "~/.dotfiles/install.sh";
  };
}
