{
  config,
  lib,
  pkgs,
  ...
}:
{
  home.packages =
    lib.mkIf (config.programs.nixvim.enable && config.programs.nixvim.lsp.servers.csharp_ls.enable)
      [
        pkgs.csharp-ls
        pkgs.dotnet-sdk_10
      ];
  programs.nixvim = { config, lib, ... }: {
    config = lib.mkIf config.enable {
      lsp.servers.csharp_ls = {
        enable = true;
        package = null;
      };
    };
  };
}
