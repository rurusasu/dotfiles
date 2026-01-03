# Nixvim configuration
# Options are defined in nix/modules/home/nixvim/
# Plugin configurations are in ./plugins/
{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.myHomeSettings.nixvim;
  tabKeys = config.myHomeSettings.terminals.keybindings.tab;
  paneZoomKey = config.myHomeSettings.terminals.keybindings.paneZoom;
in
{
  imports = [
    ./plugins
  ];

  config = mkIf cfg.enable {
    programs.nixvim = {
      enable = true;
      defaultEditor = true;
      viAlias = true;
      vimAlias = true;

      # Leader keys from module config
      globals = {
        mapleader = cfg.leader;
        maplocalleader = cfg.localLeader;
      };

      # Colorscheme from module config
      colorschemes.${cfg.colorscheme.name} = {
        enable = true;
        settings.style = cfg.colorscheme.style;
      };

      # Keymaps
      keymaps = [
        { mode = "n"; key = "<leader>e"; action = "<cmd>NvimTreeToggle<cr>"; options.desc = "Explorer"; }
        # Tab (buffer) management (using shared keybindings)
        { mode = "n"; key = "<leader>${tabKeys.new}"; action = "<cmd>tabnew<cr>"; options.desc = "New tab"; }
        { mode = "n"; key = "<leader>${tabKeys.close}"; action = "<cmd>tabclose<cr>"; options.desc = "Close tab"; }
        { mode = "n"; key = "<leader>${tabKeys.next}"; action = "<cmd>tabnext<cr>"; options.desc = "Next tab"; }
        { mode = "n"; key = "<leader>${tabKeys.prev}"; action = "<cmd>tabprevious<cr>"; options.desc = "Previous tab"; }
        # Window zoom (using shared keybindings)
        { mode = "n"; key = "<leader>${paneZoomKey}"; action = "<cmd>only<cr>"; options.desc = "Maximize window"; }
      ];

      # Performance optimization
      performance = {
        byteCompileLua = {
          enable = true;
          nvimRuntime = true;
          configs = true;
          plugins = true;
        };
      };

      extraConfigLua = builtins.readFile ./init.lua;
    };
  };
}
