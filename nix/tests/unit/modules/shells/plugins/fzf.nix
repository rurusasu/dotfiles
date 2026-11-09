{ homeConfigurations }:
let
  inherit (homeConfigurations) homes;
in
{
  testFzfConfigurationAndShellIntegrationAcrossHomes = {
    expr = map (home: {
      inherit (home.config.programs.fzf)
        enable
        enableBashIntegration
        enableZshIntegration
        defaultOptions
        ;
    }) homes;
    expected = map (_: {
      enable = true;
      enableBashIntegration = false;
      enableZshIntegration = true;
      defaultOptions = [
        "--height=60%"
        "--layout=reverse"
        "--border"
        "--prompt=> "
      ];
    }) homes;
  };
}
