{ pkgs, ... }:
{
  # Package installation is independent of user shell settings.
  programs.fzf = {
    enable = true;
    package = pkgs.fzf;
  };
}
