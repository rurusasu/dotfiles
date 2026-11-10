{
  config,
  lib,
  pkgs,
  ...
}:
{
  home.packages =
    lib.mkIf (config.programs.nixvim.enable && config.programs.nixvim.lsp.servers.nixd.enable)
      [
        pkgs.nixd
        pkgs.nixfmt
      ];
  programs.nixvim = { config, lib, ... }: {
    config = lib.mkIf config.enable ({
      lsp.servers.nixd = {
        enable = true;
        package = null;
      };
    });
  };
}
