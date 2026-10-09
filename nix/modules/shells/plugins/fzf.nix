{ pkgs, ... }:
{
  # User shell settings live in nix/home/shells/plugins/fzf.nix.
  programs.fzf = {
    enable = true;
    package = pkgs.fzf;
  };
}
