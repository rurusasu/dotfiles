{
  inputs,
  homeConfigurations ? import ../../fixtures/home-configurations.nix { inherit inputs; },
}:
let
  inherit (homeConfigurations)
    homes
    sharedConfig
    lib
    ;
  options = lib.concatStringsSep " " sharedConfig.programs.zoxide.options;
in
{
  testZoxideShellIntegrationsAcrossHomes = {
    expr = map (
      home:
      let
        inherit (home.config) programs;
      in
      {
        enabled = programs.zoxide.enable;
        bashIntegration = programs.zoxide.enableBashIntegration;
        zshIntegration = programs.zoxide.enableZshIntegration;
        options = programs.zoxide.options;
        bashCommand = lib.hasInfix " init bash ${options}" programs.bash.initExtra;
        zshCommand = lib.hasInfix " init zsh ${options}" programs.zsh.initContent;
        zoxideInit = lib.hasInfix (builtins.unsafeDiscardStringContext "${lib.getExe programs.zoxide.package} init zsh") programs.zsh.initContent;
        customBashWidget = lib.hasInfix "__zoxide_zi_widget" programs.bash.initExtra;
        customZshWidget = lib.hasInfix "__zoxide_zi_widget" programs.zsh.initContent;
      }
    ) homes;
    expected = map (_: {
      enabled = sharedConfig.programs.zoxide.enable;
      bashIntegration = sharedConfig.programs.zoxide.enableBashIntegration;
      zshIntegration = sharedConfig.programs.zoxide.enableZshIntegration;
      options = sharedConfig.programs.zoxide.options;
      bashCommand = true;
      zshCommand = true;
      zoxideInit = true;
      customBashWidget = false;
      customZshWidget = false;
    }) homes;
  };
}
