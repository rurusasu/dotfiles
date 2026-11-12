{ homeConfigurations }:
let
  inherit (homeConfigurations) homes;
in
{
  testDirenvFlakeSupportAcrossHomes = {
    expr = map (home: {
      inherit (home.config.programs.direnv)
        enable
        enableBashIntegration
        enableZshIntegration
        ;
      nixDirenv = home.config.programs.direnv.nix-direnv.enable;
    }) homes;
    expected = map (_: {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
      nixDirenv = true;
    }) homes;
  };
}
