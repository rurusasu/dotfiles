{
  inputs,
  homeConfigurations ? import ../../fixtures/home-configurations.nix { inherit inputs; },
}:
let
  inherit (homeConfigurations) homes sharedConfig;
in
{
  testStandaloneHomesUseDeclaredGarbageCollectionSettings = {
    expr = map (home: {
      inherit (home.config.nix.gc) automatic dates options;
    }) homes;
    expected = map (_: {
      inherit (sharedConfig.nix.gc) automatic dates options;
    }) homes;
  };
}
