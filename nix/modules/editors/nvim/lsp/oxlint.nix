{
  config,
  lib,
  pkgs,
  ...
}:
{
  home.packages = lib.mkIf (
    config.programs.nixvim.enable && config.programs.nixvim.lsp.servers.oxlint.enable
  ) [ pkgs.oxlint ];
  programs.nixvim = { config, lib, ... }: {
    config = lib.mkIf config.enable {
      lsp.servers.oxlint = {
        enable = true;
        package = null;
      };
    };
  };
}
