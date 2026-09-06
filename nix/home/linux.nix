{
  pkgs,
  lib,
  inputs,
  ...
}:
let
  codexPackage = inputs."llm-agents".packages.${pkgs.stdenv.hostPlatform.system}.codex;
  sets = import ../packages/sets.nix {
    inherit pkgs lib;
    inherit codexPackage;
  };
in
{
  imports = [ ./common.nix ];

  home.packages = sets.all;

  programs.zsh.shellAliases = {
    nrs = "~/.dotfiles/install.sh";
  };
}
