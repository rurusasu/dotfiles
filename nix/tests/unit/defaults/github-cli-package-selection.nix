{ fixtures, homeConfigurations }:
{
  testGitModuleInstallsItsGitHubCredentialHelper = {
    expr = {
      darwin = builtins.elem (fixtures.mkPkgs "aarch64-darwin").gh homeConfigurations.darwin.config.home.packages;
      linux = builtins.elem (fixtures.mkPkgs "x86_64-linux").gh homeConfigurations.linux.config.home.packages;
    };
    expected = {
      darwin = true;
      linux = true;
    };
  };
}
