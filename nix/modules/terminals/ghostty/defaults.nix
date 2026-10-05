{ config, ... }:
{
  programs.ghostty = {
    enable = true;
    settings = { };
    enableBashIntegration = true;
    enableFishIntegration = false;
    enableZshIntegration = true;
    installBatSyntax = false;
  };

  xdg.configFile."ghostty/config" = {
    source = ./config.ghostty;
    onChange = "${config.programs.ghostty.package}/bin/ghostty +validate-config --config-file=${config.xdg.configHome}/ghostty/config";
  };
}
