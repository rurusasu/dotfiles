{
  config,
  lib,
  pkgs,
  platform,
  ...
}:
{
  config = lib.mkMerge [
    { programs.zoxide.enable = true; }
    (lib.mkIf config.programs.zoxide.enable {
      home.sessionVariables._ZO_EXCLUDE_DIRS = lib.mkIf (platform == "wsl") "/mnt/wsl/*:/mnt/wslg/*";
      # User shell integration is shared by Darwin, Linux, and WSL homes.
      programs.zoxide = {
        enableBashIntegration = true;
        enableZshIntegration = true;
        options = [ "--cmd cd" ];
      };
    })
  ];
}
