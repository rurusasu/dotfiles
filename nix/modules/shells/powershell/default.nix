{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.powershell;
in
{
  options.programs.powershell = {
    enable = lib.mkEnableOption "PowerShell";
    package = lib.mkPackageOption pkgs "powershell" { };
  };
  config = {
    programs.powershell.enable = true;
    home.packages = lib.mkIf cfg.enable [ cfg.package ];
  };
}
