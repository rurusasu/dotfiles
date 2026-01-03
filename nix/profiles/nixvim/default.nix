# Nixvim configuration
# Options are defined in nix/modules/home/nixvim/
{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.myHomeSettings.nixvim;
  tabKeys = config.myHomeSettings.terminals.keybindings.tab;
  paneZoomKey = config.myHomeSettings.terminals.keybindings.paneZoom;
in
{
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

      # Plugins (nixvim native configuration)
      plugins = {
        # Which-key
        which-key.enable = true;

        # File explorer
        nvim-tree = {
          enable = true;
          settings.filters.dotfiles = false;
        };

        # Fuzzy finder (conditional)
        telescope = mkIf cfg.features.telescope {
          enable = true;
          keymaps = {
            "<leader>ff" = { action = "find_files"; options.desc = "Find files"; };
            "<leader>fg" = { action = "live_grep"; options.desc = "Live grep"; };
            "<leader>fb" = { action = "buffers"; options.desc = "Buffers"; };
            "<leader>fh" = { action = "help_tags"; options.desc = "Help tags"; };
          };
        };

        # Treesitter (conditional)
        treesitter = mkIf cfg.features.treesitter {
          enable = true;
          settings = {
            ensure_installed = [
              "lua" "vim" "vimdoc" "nix" "bash"
              "python" "javascript" "typescript"
              "json" "yaml" "markdown" "markdown_inline"
            ];
            highlight.enable = true;
            indent.enable = true;
          };
        };

        # Git signs (conditional)
        gitsigns = mkIf cfg.features.git {
          enable = true;
        };

        # Status line
        lualine = {
          enable = true;
          settings.options.theme = cfg.colorscheme.name;
        };

        # Indent guides
        indent-blankline.enable = true;

        # Auto pairs
        nvim-autopairs.enable = true;

        # Comment
        comment.enable = true;

        # Surround
        nvim-surround.enable = true;

        # Web devicons
        web-devicons.enable = true;
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
