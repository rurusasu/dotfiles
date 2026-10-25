{
  inputs,
  homeConfigurations ? import ../../fixtures/home-configurations.nix { inherit inputs; },
}:
let
  inherit (homeConfigurations) homes lib;
in
{
  testBatSettingsAcrossHomes = {
    expr = map (home: {
      enabled = home.config.programs.bat.enable;
      packageName = home.config.programs.bat.package.pname;
      config = home.config.xdg.configFile."bat/config".text;
      manPager = home.config.home.sessionVariables.MANPAGER;
      manRoffOptions = home.config.home.sessionVariables.MANROFFOPT;
    }) homes;
    expected = map (
      home:
      let
        configuredBat = import ../../../modules/shells/plugins/bat.nix {
          inherit (home) config pkgs;
          inherit (home.pkgs) lib;
        };
      in
      {
        enabled = true;
        packageName = "bat";
        config =
          lib.generators.toKeyValue {
            mkKeyValue = name: value: "--${name}=${lib.escapeShellArg value}";
            listsAsDuplicateKeys = true;
          } (lib.filterAttrs (_: value: !(builtins.isBool value)) home.config.programs.bat.config)
          + lib.concatMapStrings (name: "--${name}\n") (
            builtins.attrNames (
              lib.filterAttrs (_: value: builtins.isBool value && value) home.config.programs.bat.config
            )
          );
        manPager = configuredBat.home.sessionVariables.MANPAGER;
        manRoffOptions = configuredBat.home.sessionVariables.MANROFFOPT;
      }
    ) homes;
  };
}
