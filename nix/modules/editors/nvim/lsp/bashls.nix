{
  config,
  lib,
  pkgs,
  ...
}:
{
  home.packages = lib.mkIf (
    config.programs.nixvim.enable && config.programs.nixvim.lsp.servers.bashls.enable
  ) [ pkgs.bash-language-server ];
  programs.nixvim = { config, lib, ... }: {
    config = lib.mkIf config.enable {
      lsp.servers.bashls = {
        enable = true;
        package = null;
      };
    };
  };
}
