{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
{
  options.programs.dia = {
    enable = lib.mkEnableOption "Dia browser";
    package = lib.mkOption {
      type = lib.types.package;
      default = import ./package.nix { inherit inputs pkgs; };
      defaultText = lib.literalExpression "the Dia distribution from inputs.dia";
      description = "Dia browser package.";
    };
  };
  config = lib.mkIf config.programs.dia.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.system == "aarch64-darwin";
        message = "Dia is supported only on aarch64-darwin.";
      }
    ];
    home.packages = [ config.programs.dia.package ];
  };
}
