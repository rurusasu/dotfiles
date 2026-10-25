{
  inputs,
  homeConfigurations ? import ../../../../fixtures/home-configurations.nix { inherit inputs; },
}:
let
  inherit (homeConfigurations) homes lib;
  aliasNames = [
    "eza"
    "ls"
    "ll"
    "la"
    "lt"
    "lla"
  ];
in
{
  testEzaZshAliasesUseConfiguredListingOptionsAcrossHomes = {
    expr = map (
      home:
      let
        inherit (home.config) programs;
      in
      {
        enabled = programs.eza.enable;
        zshIntegration = programs.eza.enableZshIntegration;
        packageName = programs.eza.package.pname;
        optionsAlias = programs.zsh.shellAliases.eza;
        aliasesGenerated = map (
          name:
          lib.hasInfix
            "alias -- ${lib.escapeShellArg name}=${lib.escapeShellArg programs.zsh.shellAliases.${name}}"
            home.config.home.file."${lib.removePrefix "${home.config.home.homeDirectory}/" programs.zsh.dotDir}/.zshrc".text
        ) aliasNames;
      }
    ) homes;
    expected = map (
      home:
      let
        cfg = home.config.programs.eza;
      in
      {
        enabled = true;
        zshIntegration = true;
        packageName = "eza";
        optionsAlias = "eza ${
          lib.escapeShellArgs (
            lib.optionals (cfg.icons != null) [
              "--icons"
              cfg.icons
            ]
            ++ lib.optionals (cfg.colors != null) [
              "--color"
              cfg.colors
            ]
            ++ lib.optional cfg.git "--git"
            ++ cfg.extraOptions
          )
        }";
        aliasesGenerated = map (_: true) aliasNames;
      }
    ) homes;
  };
}
