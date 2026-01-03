# which-key - keybinding hints
{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.myHomeSettings.nixvim;
in
{
  config = mkIf cfg.enable {
    programs.nixvim.plugins.which-key = {
      enable = true;
      package = pkgs.vimPlugins.which-key-nvim;
    };
  };
}
