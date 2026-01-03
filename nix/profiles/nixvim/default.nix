{ pkgs, ... }:
{
  programs.nixvim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;

    # Colorscheme
    colorschemes.tokyonight = {
      enable = true;
      settings.style = "night";
    };

    # Plugins (nixvim native configuration)
    plugins = {
      # Which-key
      which-key.enable = true;

      # File explorer
      nvim-tree = {
        enable = true;
        filters.dotfiles = false;
      };

      # Fuzzy finder
      telescope = {
        enable = true;
        keymaps = {
          "<leader>ff" = { action = "find_files"; options.desc = "Find files"; };
          "<leader>fg" = { action = "live_grep"; options.desc = "Live grep"; };
          "<leader>fb" = { action = "buffers"; options.desc = "Buffers"; };
          "<leader>fh" = { action = "help_tags"; options.desc = "Help tags"; };
        };
      };

      # Treesitter
      treesitter = {
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

      # Git signs
      gitsigns.enable = true;

      # Status line
      lualine = {
        enable = true;
        settings.options.theme = "tokyonight";
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
}
