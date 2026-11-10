{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.deepseek-harness;
in
{
  options.programs.deepseek-harness = {
    enable = lib.mkEnableOption "DeepSeek Harness";
    package = lib.mkOption {
      type = lib.types.package;
      default =
        if pkgs.stdenv.hostPlatform.isDarwin then
          inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.dsh
        else
          pkgs.deepseek-harness;
      description = "DeepSeek Harness package for this platform.";
    };
  };
  config = {
    programs.deepseek-harness.enable = true;
    home.packages = lib.mkIf cfg.enable [ cfg.package ];
  };
}
