{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.programs.beeper = {
    enable = lib.mkEnableOption "Beeper";
    package = lib.mkPackageOption pkgs "beeper" { };
  };

  config = lib.mkMerge [
    {
      programs.beeper.enable = lib.mkIf (lib.meta.availableOn pkgs.stdenv.hostPlatform pkgs.beeper) true;
    }
    (lib.mkIf config.programs.beeper.enable {
      home.packages = [ config.programs.beeper.package ];
    })
  ];
}
