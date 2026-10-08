{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
let
  sets = import ../../packages/sets.nix {
    inherit pkgs lib;
  };
  inherit ((import ../../modules/fonts.nix { inherit pkgs; })) fonts;
in
{
  home.homeDirectory = lib.mkDefault "/home/${config.home.username}";

  imports = [
    ../../modules/editors/nvim
    ../../modules/discord
    ../../home/common.nix
  ];

  home.packages = sets.allWithout sets.nativeDesktopPackageNames ++ fonts.packages;
  fonts.fontconfig = fonts.fontconfig;

  programs.git.signing.signer = "/opt/1Password/op-ssh-sign";

  programs.zsh.shellAliases = {
    nrs = "~/.dotfiles/install.sh";
  };
}
