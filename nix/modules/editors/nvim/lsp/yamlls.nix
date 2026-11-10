{
  config,
  lib,
  pkgs,
  ...
}:
{
  home.packages = lib.mkIf (
    config.programs.nixvim.enable && config.programs.nixvim.lsp.servers.yamlls.enable
  ) [ pkgs.yaml-language-server ];
  programs.nixvim = { config, lib, ... }: {
    config = lib.mkIf config.enable {
      lsp.servers.yamlls = {
        enable = true;
        package = null;
      };
    };
  };
}
