{ inputs }:
let
  fixtures = import ../fixtures/packages.nix { inherit inputs; };
in
{
  testHostModulesIncludeGitHubCliForDarwinAndLinux = {
    expr = {
      darwin = builtins.elem (fixtures.mkPkgs "aarch64-darwin").gh fixtures.darwin.config.environment.systemPackages;
      linux =
        builtins.elem (fixtures.mkPkgs "x86_64-linux").gh
          (fixtures.mkHome "x86_64-linux" [ (import ../../hosts { inherit inputs; }).linuxHome ])
          .config.home.packages;
    };
    expected = {
      darwin = true;
      linux = true;
    };
  };
}
