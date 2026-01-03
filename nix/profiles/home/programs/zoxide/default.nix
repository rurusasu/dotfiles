{ pkgs, ... }:
{
  programs.zoxide = {
    enable = true;
    package = pkgs.zoxide;
    enableBashIntegration = true;
    enableZshIntegration = true;
    options = [
      "--cmd cd"
    ];
  };
}
