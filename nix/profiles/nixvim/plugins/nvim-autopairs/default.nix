# nvim-autopairs - auto bracket pairing
{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.myHomeSettings.nixvim;
in
{
  config = mkIf cfg.enable {
    programs.nixvim.plugins.nvim-autopairs = {
      enable = true;
      package = pkgs.vimPlugins.nvim-autopairs;
      settings = {
        check_ts = true;
        disable_filetype = [ "TelescopePrompt" ];
      };
    };
  };
}
