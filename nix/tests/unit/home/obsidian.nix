{
  inputs,
  homeConfigurations ? import ../../fixtures/home-configurations.nix { inherit inputs; },
}:
let
  inherit (homeConfigurations)
    linux
    wsl
    darwinPackages
    ;
in
{
  testObsidianIsSelectedByPlatformModules = {
    expr = {
      darwin = darwinPackages.contains darwinPackages.pkgs.obsidian darwinPackages.system;
      linux = builtins.any (package: (package.pname or "") == "obsidian") linux.config.home.packages;
      wsl = builtins.any (package: (package.pname or "") == "obsidian") wsl.config.home.packages;
    };
    expected = {
      darwin = true;
      linux = true;
      wsl = true;
    };
  };
}
