{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = lib.mkMerge [
    {
      programs.obsidian.enable = lib.mkIf (lib.meta.availableOn pkgs.stdenv.hostPlatform pkgs.obsidian) true;
    }
    (lib.mkIf config.programs.obsidian.enable {
      programs.obsidian.package = lib.mkDefault pkgs.obsidian;
    })
  ];
}
