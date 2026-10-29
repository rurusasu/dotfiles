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
  options.programs.strata = {
    enable = lib.mkEnableOption "Strata desktop and control CLI";
    package = lib.mkOption {
      type = lib.types.package;
      default = selected.desktop;
      defaultText = lib.literalExpression "the Strata desktop distribution from inputs.strata-release";
      description = "Strata desktop package.";
    };
  };
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
      config.programs.strata.package
      selected.control
    ];
  };
}
