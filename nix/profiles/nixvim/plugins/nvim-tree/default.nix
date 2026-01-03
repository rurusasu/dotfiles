# nvim-tree - file explorer
{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.myHomeSettings.nixvim;
in
{
  config = mkIf cfg.enable {
    programs.nixvim.plugins.nvim-tree = {
      enable = true;
      package = pkgs.vimPlugins.nvim-tree-lua;
      settings.filters.dotfiles = false;
    };
  };
}
