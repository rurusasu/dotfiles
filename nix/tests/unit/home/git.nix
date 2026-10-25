{
  inputs,
  homeConfigurations ? import ../../fixtures/home-configurations.nix { inherit inputs; },
}:
let
  inherit (homeConfigurations) homes;
in
{
  testGitSettingsAreRenderedForEachHome = {
    expr = map (home: home.config.xdg.configFile."git/config".text) homes;
    expected = map (
      home:
      let
        inherit (home.pkgs) lib;
        git = home.config.programs.git;
        inherit (git) signing;
        signingDefaults =
          lib.optionalAttrs (signing.key != null) {
            user.signingKey = signing.key;
          }
          // lib.optionalAttrs (signing.signByDefault != null) {
            commit.gpgSign = signing.signByDefault;
            tag.gpgSign = signing.signByDefault;
          }
          // lib.optionalAttrs (signing.format != null) {
            gpg = {
              inherit (signing) format;
              ${signing.format}.program = signing.signer;
            };
          };
      in
      lib.generators.toGitINI (lib.recursiveUpdate signingDefaults git.settings)
    ) homes;
  };

  testGitIsInstalledOnceWithRelativeWorktrees = {
    expr = map (
      home:
      let
        git = home.config.programs.git;
        inherit (git) settings;
        countPackageEntries =
          target: home.pkgs.lib.count (package: package.drvPath == target.drvPath) home.config.home.packages;
      in
      {
        enabled = git.enable;
        gitCopies = countPackageEntries git.package;
        relativeWorktrees = settings.worktree.useRelativePaths or false;
      }
    ) homes;
    expected = map (_: {
      enabled = true;
      gitCopies = 1;
      relativeWorktrees = true;
    }) homes;
  };

  testHomeGitHasNoMutableCheckoutTrustIncludes = {
    expr = map (home: home.config.programs.git.includes) homes;
    expected = map (_: [ ]) homes;
  };

  testNativeGitOwnsItsFilesWithoutBackups = {
    expr = map (home: {
      gitForce = home.config.xdg.configFile."git/config".force;
      legacyGitForce = home.config.home.file.".gitconfig".force;
      legacyGitHasNoSettings = !(home.pkgs.lib.hasInfix "[" home.config.home.file.".gitconfig".text);
    }) homes;
    expected = map (_: {
      gitForce = true;
      legacyGitForce = true;
      legacyGitHasNoSettings = true;
    }) homes;
  };
}
