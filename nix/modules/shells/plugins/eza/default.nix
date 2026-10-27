{ config, lib, ... }:
let
  listingOptions = "--group-directories-first --time-style=long-iso";
  gitOptions = "${listingOptions} --git";
in
{
  config = lib.mkIf config.programs.eza.enable {
    programs.eza = {
      enableZshIntegration = true;
      enableBashIntegration = false;
      enableFishIntegration = false;
      enableIonIntegration = false;
      enableNushellIntegration = false;
      icons = "auto";
      colors = "auto";
      extraOptions = [ "--tree" ];
    };

    programs.zsh.shellAliases = lib.mkIf config.programs.zsh.enable {
      ls = "eza --level=1";
      ll = "eza --level=1 ${listingOptions}";
      la = "eza --level=1 ${gitOptions} --hyperlink -F";
      lt = "eza --level=2 ${gitOptions}";
    };
  };
}
