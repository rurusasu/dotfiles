{ pkgs, ... }:
{
  # User shell settings live in nix/home/shells/plugins/zoxide.nix.
  programs.zoxide = {
    enable = true;
    package = pkgs.zoxide;
  };
}
