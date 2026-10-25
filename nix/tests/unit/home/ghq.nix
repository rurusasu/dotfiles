{
  inputs,
  homeConfigurations ? import ../../fixtures/home-configurations.nix { inherit inputs; },
}:
let
  inherit (homeConfigurations)
    homes
    wsl
    lib
    ;
in
{
  testGhqRootsAreRenderedForEachHome = {
    expr = map (home: {
      rootsInGitConfig = home.pkgs.lib.hasInfix (home.pkgs.lib.generators.toGitINI {
        ghq.root = home.config.programs.git.settings.ghq.root;
      }) home.config.xdg.configFile."git/config".text;
      packageEntries = home.pkgs.lib.count (
        package: package.drvPath == home.pkgs.ghq.drvPath
      ) home.config.home.packages;
    }) homes;
    expected = map (_: {
      rootsInGitConfig = true;
      packageEntries = 1;
    }) homes;
  };

  testWslGhqRootsUseWindowsDrives = {
    expr =
      let
        roots = lib.toList wsl.config.programs.git.settings.ghq.root;
      in
      roots != [ ] && builtins.all (root: builtins.match "/mnt/[a-z](/.*)?" root != null) roots;
    expected = true;
  };
}
