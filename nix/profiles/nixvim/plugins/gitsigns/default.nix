# Gitsigns - git decorations
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.myHomeSettings.nixvim;
in
{
  config = mkIf (cfg.enable && cfg.features.git) {
    programs.nixvim.plugins.gitsigns = {
      enable = true;
      package = pkgs.vimPlugins.gitsigns-nvim;
    };
  };
}
