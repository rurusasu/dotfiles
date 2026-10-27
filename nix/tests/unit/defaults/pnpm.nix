{ homeConfigurations }:
let
  inherit (homeConfigurations) homes;
in
{
  testPnpmIsNotInstalled = {
    expr = map (home: {
      enabled = home.config.programs.pnpm.enable;
      environment = home.config.home.sessionVariables ? PNPM_HOME;
    }) homes;
    expected = map (_: {
      enabled = false;
      environment = false;
    }) homes;
  };
}
