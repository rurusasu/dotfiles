# Comment - code commenting
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
  config = mkIf cfg.enable {
    programs.nixvim.plugins.comment = {
      enable = true;
      package = pkgs.vimPlugins.comment-nvim;
    };
  };
}
