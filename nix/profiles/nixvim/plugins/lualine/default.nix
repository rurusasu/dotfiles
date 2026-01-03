# Lualine - status line
{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.myHomeSettings.nixvim;
in
{
  config = mkIf cfg.enable {
    programs.nixvim.plugins.lualine = {
      enable = true;
      package = pkgs.vimPlugins.lualine-nvim;
      settings.options.theme = cfg.colorscheme.name;
    };
  };
}
