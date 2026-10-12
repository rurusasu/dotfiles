{ config, ... }:
{
  imports = [ (import ../../tools.nix).ghostty ];
  programs.ghostty = {
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
