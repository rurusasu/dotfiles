{ homeConfigurations }:
let
  inherit (homeConfigurations) homes;
in
{
  testRustToolsOutrankRetainedRustupAcrossHomes = {
    expr = map (
      home:
      let
        priority =
          target:
          (builtins.head (
            builtins.filter (package: package.drvPath == target.drvPath) home.config.home.packages
          )).meta.priority or 5;
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
