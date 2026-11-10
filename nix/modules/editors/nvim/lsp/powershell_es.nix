{
  config,
  lib,
  pkgs,
  ...
}:
let
  powershell = config.programs.powershell;
in
{
  home.packages = lib.mkIf (
    config.programs.nixvim.enable && config.programs.nixvim.lsp.servers.powershell_es.enable
  ) [ pkgs.powershell-editor-services ];
  programs.nixvim =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      config = lib.mkIf (config.enable && powershell.enable) {
        lsp.servers.powershell_es = {
          enable = true;
          package = null;
          config = {
            shell = lib.getExe' powershell.package "pwsh";
            bundle_path = "${pkgs.powershell-editor-services}/lib/powershell-editor-services";
          };
        };
      };
    };
}
