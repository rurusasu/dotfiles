{ homeConfigurations }:
let
  inherit (homeConfigurations)
    homes
    lib
    ;
in
{
  testRipgrepSettingsAcrossHomes = {
    expr = map (home: {
      enabled = home.config.programs.ripgrep.enable;
      packageName = home.config.programs.ripgrep.package.pname;
      configPath = home.config.home.sessionVariables.RIPGREP_CONFIG_PATH;
      config = home.config.home.file."${home.config.xdg.configHome}/ripgrep/ripgreprc".text;
    }) homes;
    expected = map (home: {
      enabled = true;
      packageName = "ripgrep";
      configPath = "${home.config.xdg.configHome}/ripgrep/ripgreprc";
      config = lib.concatLines home.config.programs.ripgrep.arguments;
    }) homes;
  };

}
