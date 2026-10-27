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
        assertion = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
        message = "Strata is supported only on x86_64-linux.";
      }
    ];
    home.packages = [
      selected.desktop
      selected.control
    ];
  };
}
