{ fixtures, homeConfigurations }:
{
  testHostModulesIncludeGitHubCliForDarwinAndLinux = {
    expr = {
      darwin = builtins.elem (fixtures.mkPkgs "aarch64-darwin").gh fixtures.darwin.config.environment.systemPackages;
      linux = builtins.elem (fixtures.mkPkgs "x86_64-linux").gh homeConfigurations.linux.config.home.packages;
    };
    expected = {
      darwin = true;
      linux = true;
    };
  };
}
