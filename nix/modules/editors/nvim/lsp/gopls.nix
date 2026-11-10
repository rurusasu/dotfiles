{
  config,
  lib,
  pkgs,
  ...
}:
{
  home.packages =
    lib.mkIf (config.programs.nixvim.enable && config.programs.nixvim.lsp.servers.gopls.enable)
      [
        pkgs.go
        pkgs.gopls
      ];
  programs.nixvim = { config, lib, ... }: {
    config = lib.mkIf config.enable {
      lsp.servers.gopls = {
        enable = true;
        package = null;
      };
    };
  };
}
