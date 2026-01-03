# Nixvim shared options module
{ config, lib, ... }:
with lib;
{
  options.myHomeSettings.nixvim = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable Nixvim (Neovim configured with Nix)";
    };

    leader = mkOption {
      type = types.str;
      default = " ";
      description = "Vim leader key (default: Space)";
    };

    localLeader = mkOption {
      type = types.str;
      default = "\\";
      description = "Vim local leader key";
    };

    colorscheme = {
      name = mkOption {
        type = types.str;
        default = "tokyonight";
        description = "Colorscheme to use";
      };
      style = mkOption {
        type = types.str;
        default = "night";
        description = "Colorscheme style variant";
      };
    };

    features = {
      lsp = mkOption {
        type = types.bool;
        default = true;
        description = "Enable LSP support";
      };
      treesitter = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Treesitter";
      };
      telescope = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Telescope fuzzy finder";
      };
      git = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Git integration (gitsigns, etc.)";
      };
    };
  };
}
