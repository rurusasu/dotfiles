{
  config,
  lib,
  pkgs,
  ...
}:
{
  home.packages = lib.mkIf (
    config.programs.nixvim.enable && config.programs.nixvim.lsp.servers.ty.enable
  ) [ pkgs.ty ];
  programs.nixvim = { config, lib, ... }: {
    config = lib.mkIf config.enable ({
      lsp.servers.ty = {
        enable = true;
        package = null;
      };
    });
  };
}
