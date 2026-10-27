{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  selected = import ./package.nix {
    inherit pkgs;
    release = import ./release.nix (builtins.fromJSON (builtins.readFile inputs.strata-release));
  };
in
{
  options.programs.strata.enable = lib.mkEnableOption "Strata desktop and control CLI";
  config = lib.mkIf config.programs.strata.enable {
    assertions = [
      {
        assertion = builtins.elem pkgs.stdenv.hostPlatform.system [
          "x86_64-linux"
          "aarch64-darwin"
        ];
        message = "Strata is supported on x86_64-linux and aarch64-darwin.";
      }
    ];
    home.packages = [
      selected.desktop
      selected.control
    ];
  };
}
