{
  config,
  lib,
  pkgs,
  ...
}:
{
  home.packages = lib.mkIf (
    config.programs.nixvim.enable && config.programs.nixvim.lsp.servers.ruff.enable
  ) [ pkgs.ruff ];
  programs.nixvim = { config, lib, ... }: {
    config = lib.mkIf config.enable {
      lsp.servers.ruff = {
        enable = true;
        package = null;
        # hover は併用する ty に任せる（Ruff 公式の併用例）。
        config.on_attach.__raw = ''
          function(client)
            client.server_capabilities.hoverProvider = false
          end
        '';
      };
    };
  };
}
