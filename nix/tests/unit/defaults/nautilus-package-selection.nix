{
  inputs,
  homeConfigurations ? import ../../fixtures/home-configurations.nix { inherit inputs; },
}:
{
  testNautilusIsUnavailableOnDarwin = {
    expr = builtins.any (
      package: (package.pname or "") == "nautilus"
    ) homeConfigurations.darwin.config.home.packages;
    expected = false;
  };
}
