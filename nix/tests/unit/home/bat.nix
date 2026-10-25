{
  inputs,
  homeConfigurations ? import ../../fixtures/home-configurations.nix { inherit inputs; },
}:
let
  inherit (homeConfigurations) homes sharedConfig;
in
{
  testBatSettingsAcrossHomes = {
    expr = map (home: {
      enabled = home.config.programs.bat.enable;
      packageName = home.config.programs.bat.package.pname;
      config = home.config.programs.bat.config;
      manPager = home.config.home.sessionVariables.MANPAGER;
      manRoffOptions = home.config.home.sessionVariables.MANROFFOPT;
    }) homes;
    expected = map (
      home:
      let
        configuredBat = import ../../../home/shells/plugins/bat.nix {
          inherit (home) pkgs;
          inherit (home.pkgs) lib;
          config.programs.bat.package = home.pkgs.bat;
        };
      in
      {
        enabled = sharedConfig.programs.bat.enable;
        packageName = sharedConfig.programs.bat.package.pname;
        config = sharedConfig.programs.bat.config;
        manPager = configuredBat.home.sessionVariables.MANPAGER;
        manRoffOptions = sharedConfig.home.sessionVariables.MANROFFOPT;
      }
    ) homes;
  };
}
