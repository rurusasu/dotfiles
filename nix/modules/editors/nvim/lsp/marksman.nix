{
  config,
  lib,
  pkgs,
  ...
}:
{
  home.packages = lib.mkIf (
    config.programs.nixvim.enable && config.programs.nixvim.lsp.servers.marksman.enable
  ) [ pkgs.marksman ];
  programs.nixvim = { config, lib, ... }: {
    config = lib.mkIf config.enable {
      lsp.servers.marksman = {
        enable = true;
        package = null;
      };
    };
  };
}
