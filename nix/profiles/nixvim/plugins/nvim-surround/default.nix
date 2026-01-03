# nvim-surround - text surrounding manipulation
{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.myHomeSettings.nixvim;
in
{
  config = mkIf cfg.enable {
    programs.nixvim.plugins.nvim-surround = {
      enable = true;
      package = pkgs.vimPlugins.nvim-surround;
    };
  };
}
