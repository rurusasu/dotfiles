{ pkgs, ... }:
{
  programs.ripgrep = {
    enable = true;
    package = pkgs.ripgrep;
    arguments = [
      "--smart-case"
      "--hidden"
      "--glob=!.git/*"
    ];
  };
}
