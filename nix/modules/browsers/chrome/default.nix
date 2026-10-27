{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.programs.chromium.wslIntegration.enable =
    lib.mkEnableOption "Chrome locale and fcitx integration for WSL";
  config = lib.mkIf config.programs.chromium.enable (
    lib.mkMerge [
      { programs.chromium.package = lib.mkDefault pkgs.google-chrome; }
      (lib.mkIf config.programs.chromium.wslIntegration.enable {
        assertions = [
          {
            assertion = pkgs.stdenv.hostPlatform.isLinux;
            message = "Chrome WSL integration requires Linux.";
          }
        ];
        programs.chromium.package = import ./package.nix { inherit pkgs; };
        home.sessionVariables.BROWSER = lib.getExe config.programs.chromium.finalPackage;
      })
    ]
  );
}
