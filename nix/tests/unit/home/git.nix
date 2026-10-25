{
  inputs,
  homeConfigurations ? import ../../fixtures/home-configurations.nix { inherit inputs; },
}:
let
  inherit (homeConfigurations) homes sharedConfig;
  sharedGit = sharedConfig.programs.git;
in
{
  testGitNativeSettingsAreSharedAcrossHomes = {
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
        identity = settings.user;
        inherit (settings) core;
        credentials = settings.credential;
        signing = {
          inherit (git.signing) format key signByDefault;
        };
        gtrAlias = settings.alias.gtr;
      }
    ) homes;
    expected = map (_: {
      enabled = sharedGit.enable;
      gitCopies = 1;
      relativeWorktrees = true;
      identity = sharedGit.settings.user;
      core = sharedGit.settings.core;
      credentials = sharedGit.settings.credential;
      signing = {
        inherit (sharedGit.signing) format key signByDefault;
      };
      gtrAlias = sharedGit.settings.alias.gtr;
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
      gitTextHasIdentity =
        home.pkgs.lib.hasInfix "email = ${builtins.toJSON sharedGit.settings.user.email}"
          home.config.xdg.configFile."git/config".text;
    }) homes;
    expected = map (_: {
      gitForce = true;
      legacyGitForce = true;
      legacyGitHasNoSettings = true;
      gitTextHasIdentity = true;
    }) homes;
  };
}
