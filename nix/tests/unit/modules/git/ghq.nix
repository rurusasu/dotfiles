{
  inputs,
  homeConfigurations ? import ../../../fixtures/home-configurations.nix { inherit inputs; },
}:
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
        ghq.root = home.config.programs.git.settings.ghq.root;
      }) home.config.xdg.configFile."git/config".text
    ) homes;
    expected = map (_: true) homes;
  };

  testWslGhqRootsUseWindowsDrives = {
    expr =
      let
        roots = homeConfigurations.lib.toList homeConfigurations.wsl.config.programs.git.settings.ghq.root;
      in
      roots != [ ] && builtins.all (root: builtins.match "/mnt/[a-z](/.*)?" root != null) roots;
    expected = true;
  };
}
