# web-devicons - file type icons
{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.myHomeSettings.nixvim;
in
{
  config = mkIf cfg.enable {
    programs.nixvim.plugins.web-devicons = {
      enable = true;
      package = pkgs.vimPlugins.nvim-web-devicons;
      settings.strict = true;
    };
  };
}
