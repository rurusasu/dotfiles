{ fixtures }:
let
  home = fixtures.mkHome "x86_64-linux" [
    {
      programs.ghq = {
        enable = true;
        root = "/tmp/custom-ghq";
      };
      programs.git.enable = false;
    }
  ];
in
{
  testGhqRootWithoutManagedGit = {
    expr = home.config.home.sessionVariables.GHQ_ROOT;
    expected = "/tmp/custom-ghq";
  };
}
