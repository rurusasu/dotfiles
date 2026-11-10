{ homeConfigurations }:
let
  inherit (homeConfigurations) homes;
in
{
  testGwqSettingsAcrossHomes = {
    expr = map (home: home.config.programs.gwq.settings) homes;
    expected = map (home: {
      worktree = {
        basedir = home.config.home.homeDirectory + "/worktrees";
        auto_mkdir = true;
      };
      cd.launch_shell = false;
    }) homes;
  };
}
