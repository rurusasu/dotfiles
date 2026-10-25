{
  inputs,
  homeConfigurations ? import ../../fixtures/home-configurations.nix { inherit inputs; },
}:
let
  inherit (homeConfigurations) homes sharedConfig;
  aliasNames = [
    "eza"
    "ls"
    "ll"
    "la"
    "lt"
    "lla"
  ];
  aliases =
    config:
    builtins.listToAttrs (
      map (name: {
        inherit name;
        value = config.programs.zsh.shellAliases.${name};
      }) aliasNames
    );
in
{
  testEzaZshAliasesUseConfiguredListingOptionsAcrossHomes = {
    expr = map (home: {
      enabled = home.config.programs.eza.enable;
      zshIntegration = home.config.programs.eza.enableZshIntegration;
      packageName = home.config.programs.eza.package.pname;
      aliases = aliases home.config;
    }) homes;
    expected = map (_: {
      enabled = sharedConfig.programs.eza.enable;
      zshIntegration = sharedConfig.programs.eza.enableZshIntegration;
      packageName = sharedConfig.programs.eza.package.pname;
      aliases = aliases sharedConfig;
    }) homes;
  };
}
