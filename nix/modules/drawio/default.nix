{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.programs.drawio.enable = lib.mkEnableOption "draw.io Desktop";

  config = lib.mkMerge [
    {
      programs.drawio.enable = lib.mkIf (lib.meta.availableOn pkgs.stdenv.hostPlatform pkgs.drawio) true;
    }
    (lib.mkIf config.programs.drawio.enable {
      home.packages = [ pkgs.drawio ];
    })
  ];
}
