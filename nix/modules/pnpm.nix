{ pkgs, ... }:
{
  programs.pnpm = {
    enable = true;
    package = pkgs.pnpm;
  };
}
