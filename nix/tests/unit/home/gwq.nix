{
  inputs,
  homeConfigurations ? import ../../fixtures/home-configurations.nix { inherit inputs; },
}:
let
  inherit (homeConfigurations)
    homes
    wsl
    ;
in
{
  testGwqSettingsGenerateEachHomesConfiguration = {
    expr = map (
      home:
      let
        countPackageEntries =
          target: home.pkgs.lib.count (package: package.drvPath == target.drvPath) home.config.home.packages;
      in
      {
        packageEntries = countPackageEntries home.pkgs.gwq;
        configSource = home.config.xdg.configFile."gwq/config.toml".source.drvPath;
      }
    ) homes;
    expected = map (home: {
      packageEntries = 1;
      configSource =
        ((home.pkgs.formats.toml { }).generate "gwq-config.toml" home.config.dotfiles.gwq.settings).drvPath;
    }) homes;
  };

  testWslGwqWorktreesUseAWindowsDrive = {
    expr = builtins.match "/mnt/[a-z]/.+" wsl.config.dotfiles.gwq.settings.worktree.basedir != null;
    expected = true;
  };
}
