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

  # Exclude WSL system directories from zoxide
  home.sessionVariables = {
    _ZO_EXCLUDE_DIRS = "/mnt/wsl/*:/mnt/wslg/*";
  };
}
