# Treesitter - syntax highlighting and parsing
{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.myHomeSettings.nixvim;
in
{
  config = mkIf (cfg.enable && cfg.features.treesitter) {
    programs.nixvim.plugins.treesitter = {
      enable = true;
      # Use nixGrammars instead of ensure_installed to avoid read-only store errors
      nixGrammars = true;
      settings = {
        highlight.enable = true;
        indent.enable = true;
      };
      # Grammars installed via Nix (not runtime download)
      grammarPackages = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
        lua vim vimdoc nix bash
        python javascript typescript
        json yaml markdown markdown_inline
      ];
    };
  };
}
