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
    ;
  sharedSettings = sharedConfig.dotfiles.gwq.settings;
in
{
  testGwqKeepsWslWorktreesOnTheWindowsDrive = {
    expr = map (
      home:
      let
        countPackageEntries =
          target: home.pkgs.lib.count (package: package.drvPath == target.drvPath) home.config.home.packages;
      in
      {
        packageEntries = countPackageEntries home.pkgs.gwq;
        settings = home.config.dotfiles.gwq.settings;
      }
    ) homes;
    expected =
      map
        (settings: {
          packageEntries = 1;
          inherit settings;
        })
        [
          sharedSettings
          (
            sharedSettings
            // {
              worktree = sharedSettings.worktree // {
                basedir = wslDeclarations.dotfiles.gwq.settings.worktree.basedir;
              };
            }
          )
          sharedSettings
        ];
  };

  testWslGwqWorktreesUseAWindowsDrive = {
    expr = builtins.match "/mnt/[a-z]/.+" wsl.config.dotfiles.gwq.settings.worktree.basedir != null;
    expected = true;
  };
}
