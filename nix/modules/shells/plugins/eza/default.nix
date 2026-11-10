{
  config,
  lib,
  ...
}:
let
  listingOptions = "--group-directories-first --time-style=long-iso";
  gitOptions = "${listingOptions} --git";
  bashListing = level: "eza -lha --level=${toString level} --hyperlink -F --group-directories-first";
in
{
  config = lib.mkIf config.programs.eza.enable {
    programs = {
      eza = {
        enableZshIntegration = lib.mkDefault true;
        enableBashIntegration = lib.mkDefault true;
        enableFishIntegration = false;
        enableIonIntegration = false;
        enableNushellIntegration = false;
        icons = "auto";
        colors = "auto";
        extraOptions = [ "--tree" ];
      };

      bash.shellAliases =
        lib.mkIf (config.programs.bash.enable && config.programs.eza.enableBashIntegration)
          {
            ls = bashListing 1;
            ll = bashListing 2;
            la = bashListing 2;
            l = bashListing 2;
          };
      zsh.shellAliases =
        lib.mkIf (config.programs.zsh.enable && config.programs.eza.enableZshIntegration)
          {
            ls = "eza --level=1";
            ll = "eza --level=1 ${listingOptions}";
            la = "eza --level=1 ${gitOptions} --hyperlink -F";
            lt = "eza --level=2 ${gitOptions}";
          };
    };
  };
}
