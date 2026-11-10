{
  config,
  lib,
  pkgs,
  ...
}:
{
  home.packages = lib.mkIf (
    config.programs.nixvim.enable && config.programs.nixvim.lsp.servers.taplo.enable
  ) [ pkgs.taplo ];
  programs.nixvim = { config, lib, ... }: {
    config = lib.mkIf config.enable {
      lsp.servers.taplo = {
        enable = true;
        package = null;
      };
    };
  };
}
