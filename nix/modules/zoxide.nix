{ pkgs, ... }:
{
  # Package installation is independent of user shell and platform settings.
  programs.zoxide = {
    enable = true;
    package = pkgs.zoxide;
  };
}
