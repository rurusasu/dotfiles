{ homeConfigurations, fixtures }:
let
  inherit (homeConfigurations) homes;
in
{
  testEzaDisabledShellIntegrations = {
    expr =
      let
        home = fixtures.mkHome "x86_64-linux" [
          {
            programs = {
              bash.enable = true;
              zsh.enable = true;
              eza = {
                enable = true;
                enableBashIntegration = false;
                enableZshIntegration = false;
              };
            };
          }
        ];
      in
      {
        bash = home.config.programs.bash.shellAliases.ls or null;
        zsh = home.config.programs.zsh.shellAliases.ls or null;
      };
    expected = {
      bash = null;
      zsh = null;
    };
  };
  testEzaShellIntegrationsAcrossHomes = {
    expr = map (
      home:
      let
        inherit (home.config) programs;
      in
      {
        enabled = programs.eza.enable;
        bashIntegration = programs.eza.enableBashIntegration;
        zshIntegration = programs.eza.enableZshIntegration;
        packageName = programs.eza.package.pname;
        inherit (programs.eza) icons colors extraOptions;
      }
    ) homes;
    expected = map (_: {
      enabled = true;
      bashIntegration = true;
      zshIntegration = true;
      packageName = "eza";
      icons = "auto";
      colors = "auto";
      extraOptions = [ "--tree" ];
    }) homes;
  };
}
