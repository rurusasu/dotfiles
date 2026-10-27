{ homeConfigurations }:
let
  inherit (homeConfigurations)
    homes
    lib
    ;
in
{
  testZoxideShellIntegrationsAcrossHomes = {
    expr = map (
      home:
      let
        inherit (home.config) programs;
        options = lib.concatStringsSep " " programs.zoxide.options;
        command = builtins.unsafeDiscardStringContext (lib.getExe programs.zoxide.package);
        bashrc = home.config.home.file.".bashrc".source.text;
        zshrc =
          home.config.home.file."${lib.removePrefix "${home.config.home.homeDirectory}/" programs.zsh.dotDir}/.zshrc".text;
      in
      {
        enabled = programs.zoxide.enable;
        bashIntegration = programs.zoxide.enableBashIntegration;
        zshIntegration = programs.zoxide.enableZshIntegration;
        bashCommand = lib.hasInfix ''eval "$(${command} init bash ${options})"'' bashrc;
        zshCommand = lib.hasInfix ''eval "$(${command} init zsh ${options})"'' zshrc;
        customBashWidget = lib.hasInfix "__zoxide_zi_widget" bashrc;
        customZshWidget = lib.hasInfix "__zoxide_zi_widget" zshrc;
      }
    ) homes;
    expected = map (_: {
      enabled = true;
      bashIntegration = true;
      zshIntegration = true;
      bashCommand = true;
      zshCommand = true;
      customBashWidget = false;
      customZshWidget = false;
    }) homes;
  };
}
