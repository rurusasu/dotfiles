{
  inputs,
  homeConfigurations ? import ../../fixtures/home-configurations.nix { inherit inputs; },
}:
let
  inherit (homeConfigurations) homes lib;
  bashrc = builtins.readFile ../../../modules/shells/bash/bashrc;
in
{
  testBashEnabled = {
    expr = map (home: home.config.programs.bash.enable) homes;
    expected = map (_: true) homes;
  };

  testBashConfiguration = {
    expr = map (
      home:
      let
        bash = home.config.programs.bash;
        rc = home.config.home.file.".bashrc".source.text;
        profile = home.config.home.file.".profile".source.text;
      in
      {
        userConfiguration = lib.hasInfix (builtins.unsafeDiscardStringContext bashrc) rc;
        initialization = lib.hasInfix (builtins.unsafeDiscardStringContext bash.initExtra) rc;
        loginConfiguration = lib.hasInfix (builtins.unsafeDiscardStringContext bash.profileExtra) profile;
        aliases = lib.mapAttrsToList (
          name: value:
          lib.hasInfix (builtins.unsafeDiscardStringContext "alias -- ${name}=${lib.escapeShellArg value}") rc
        ) bash.shellAliases;
      }
    ) homes;
    expected = map (home: {
      userConfiguration = true;
      initialization = true;
      loginConfiguration = true;
      aliases = lib.mapAttrsToList (_: _: true) home.config.programs.bash.shellAliases;
    }) homes;
  };
}
