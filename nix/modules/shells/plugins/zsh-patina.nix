{ lib, pkgs, ... }:
{
  # Activate after widgets and other shell integrations, as upstream recommends.
  programs.zsh.initContent = lib.mkAfter ''
    eval "$(${lib.getExe pkgs.zsh-patina} activate)"
  '';
}
