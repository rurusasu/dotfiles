{
  inputs,
  homeConfigurations ? import ../../fixtures/home-configurations.nix { inherit inputs; },
}:
let
  inherit (homeConfigurations) homes;
in
{
  testRustToolsOutrankRetainedRustupAcrossHomes = {
    expr = map (
      home:
      let
        packages = home.config.home.packages;
        selected = target: builtins.filter (package: package.drvPath == target.drvPath) packages;
        priority = target: (builtins.head (selected target)).meta.priority or 5;
      in
      {
        analyzerWins = priority home.pkgs.rust-analyzer < priority home.pkgs.rustup;
        formatterWins = priority home.pkgs.rustfmt < priority home.pkgs.rustup;
      }
    ) homes;
    expected = map (_: {
      analyzerWins = true;
      formatterWins = true;
    }) homes;
  };
}
