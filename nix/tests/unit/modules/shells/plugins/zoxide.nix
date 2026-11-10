{ homeConfigurations }:
let
  inherit (homeConfigurations) homes;
in
{
  testZoxideShellIntegrationsAcrossHomes = {
    expr = map (home: {
      inherit (home.config.programs.zoxide)
        enable
        enableBashIntegration
        enableZshIntegration
        options
        ;
    }) homes;
    expected = map (_: {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
      options = [ "--cmd cd" ];
    }) homes;
  };
}
