{
  inputs,
  homeConfigurations ? import ../../fixtures/home-configurations.nix { inherit inputs; },
}:
let
  inherit (homeConfigurations)
    homes
    wsl
    wslDeclarations
    sharedConfig
    lib
    ;
in
{
  testGhqRootsFollowThePlatformDeclarations = {
    expr = map (home: {
      root = home.config.programs.git.settings.ghq.root;
      packageEntries = home.pkgs.lib.count (
        package: package.drvPath == home.pkgs.ghq.drvPath
      ) home.config.home.packages;
    }) homes;
    expected =
      map
        (root: {
          inherit root;
          packageEntries = 1;
        })
        [
          sharedConfig.programs.git.settings.ghq.root
          wslDeclarations.programs.git.settings.ghq.root
          sharedConfig.programs.git.settings.ghq.root
        ];
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
