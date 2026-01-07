# indent-blankline - indentation guides
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
    programs.nixvim.plugins.indent-blankline = {
      enable = true;
      package = pkgs.vimPlugins.indent-blankline-nvim;
    };
  };
}
