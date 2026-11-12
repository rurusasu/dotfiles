{
  config,
  lib,
  pkgs,
  ...
}:
let
  marksman =
    if pkgs.stdenv.hostPlatform.isDarwin then
      pkgs.marksman.override {
        dotnetCorePackages = pkgs.dotnetCorePackages // {
          # MSBuild's source bootstrap fails or stalls on macOS runners.
          runtime_9_0 = pkgs.dotnetCorePackages.runtime_9_0-bin;
        };
      }
    else
      pkgs.marksman;
in
{
  home.packages = lib.mkIf (
    config.programs.nixvim.enable && config.programs.nixvim.lsp.servers.marksman.enable
  ) [ marksman ];
  programs.nixvim = { config, lib, ... }: {
    config = lib.mkIf config.enable {
      lsp.servers.marksman = {
        enable = true;
        package = null;
      };
    };
  };
}
