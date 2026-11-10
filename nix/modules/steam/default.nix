{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.steam;
in
{
  options.programs.steam = {
    enable = lib.mkEnableOption "Steam";
    package = lib.mkOption {
      type = lib.types.package;
      default =
        if pkgs.stdenv.hostPlatform.isDarwin then
          import ./package.nix { inherit inputs pkgs; }
        else
          pkgs.steam;
      description = "Steam package for this platform.";
    };
  };
  config = lib.mkMerge [
    {
      programs.steam.enable = lib.mkIf (builtins.elem pkgs.stdenv.hostPlatform.system [
        "aarch64-darwin"
        "x86_64-linux"
      ]) true;
    }
    (lib.mkIf cfg.enable {
      # NixOS owns the Steam wrapper and its 32-bit graphics dependencies.
      home.packages = lib.optionals (
        pkgs.stdenv.hostPlatform.isDarwin || !config.submoduleSupport.enable
      ) [ cfg.package ];
    })
  ];
}
