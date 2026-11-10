{ homeConfigurations }:
let
  inherit (homeConfigurations) homes;
  sharedGit = homeConfigurations.common.config.programs.git;
in
{
  testGitNativeSettingsAreSharedAcrossHomes = {
    expr = map (
      home:
      let
        git = home.config.programs.git;
        inherit (git) settings;
      in
      {
        enabled = git.enable;
        relativeWorktrees = settings.worktree.useRelativePaths or false;
        githubHttpsRewrite = settings.url."git@github.com:".insteadOf;
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
      relativeWorktrees = true;
      githubHttpsRewrite = "https://github.com/";
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

}
