{ homeConfigurations }:
let
  inherit (homeConfigurations)
    homes
    ;
in
{
  testGhqRootsAreRenderedForEachHome = {
    expr = map (
      home:
      home.pkgs.lib.hasInfix (home.pkgs.lib.generators.toGitINI {
        ghq.root = home.config.programs.ghq.root;
      }) home.config.xdg.configFile."git/config".text
    ) homes;
    expected = map (_: true) homes;
  };
}
