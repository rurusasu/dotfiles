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

  testGitIsEnabledWithRelativeWorktrees = {
    expr = map (
      home:
      let
        git = home.config.programs.git;
        inherit (git) settings;
      in
      {
        enabled = git.enable;
        relativeWorktrees = settings.worktree.useRelativePaths or false;
      }
    ) homes;
    expected = map (_: {
      enabled = true;
      relativeWorktrees = true;
    }) homes;
  };

  testHomeGitHasNoMutableCheckoutTrustIncludes = {
    expr = map (home: home.config.programs.git.includes) homes;
    expected = map (_: [ ]) homes;
  };
}
