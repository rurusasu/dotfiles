{
  inputs,
  homeConfigurations ? import ../../fixtures/home-configurations.nix { inherit inputs; },
}:
let
  inherit (homeConfigurations) darwin;
in
{
  testNautilusIsUnavailableOnDarwin = {
    expr = builtins.any (package: (package.pname or "") == "nautilus") darwin.config.home.packages;
    expected = false;
  };
}
