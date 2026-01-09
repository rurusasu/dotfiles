# Telescope - fuzzy finder
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
  config = mkIf (cfg.enable && cfg.features.telescope) {
    programs.nixvim.plugins.telescope = {
      enable = true;
      package = pkgs.vimPlugins.telescope-nvim;
      keymaps = {
        "<leader>ff" = {
          action = "find_files";
          options.desc = "Find files";
        };
        "<leader>fg" = {
          action = "live_grep";
          options.desc = "Live grep";
        };
        "<leader>fb" = {
          action = "buffers";
          options.desc = "Buffers";
        };
        "<leader>fh" = {
          action = "help_tags";
          options.desc = "Help tags";
        };
      };
    };
  };
}
