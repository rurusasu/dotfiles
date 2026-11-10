{
  config,
  lib,
  pkgs,
  ...
}:
{
  home.packages =
    lib.mkIf (config.programs.nixvim.enable && config.programs.nixvim.lsp.servers.lua_ls.enable)
      [
        pkgs.lua-language-server
        pkgs.stylua
      ];
  programs.nixvim = { config, lib, ... }: {
    config = lib.mkIf config.enable {
      lsp.servers.lua_ls = {
        enable = true;
        package = null;
      };
    };
  };
}
