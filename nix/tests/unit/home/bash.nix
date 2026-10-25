{
  inputs,
  homeConfigurations ? import ../../fixtures/home-configurations.nix { inherit inputs; },
}:
let
  fixtures = homeConfigurations;
  inherit (fixtures) homes lib sharedConfig;
  aliases = builtins.filter (line: lib.hasPrefix "alias " (lib.trim line)) (
    lib.splitString "\n" (builtins.readFile ../../../modules/shells/bash/bashrc)
  );
in
{
  testBashUserConfigurationIsGeneratedAcrossHomes = {
    expr = map (home: {
      bashEnabled = home.config.programs.bash.enable;
      bashAliases =
        aliases != [ ]
        && builtins.all (alias: lib.hasInfix alias home.config.programs.bash.initExtra) aliases;
    }) homes;
    expected = map (_: {
      bashEnabled = sharedConfig.programs.bash.enable;
      bashAliases = true;
    }) homes;
  };
}
