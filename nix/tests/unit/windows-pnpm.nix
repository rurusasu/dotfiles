{ inputs }:
{
  testNoPnpmPackagesAreDeclared = {
    expr = (import ../fixtures/packages.nix { inherit inputs; }).pnpmManifest.globalPackages;
    expected = [ ];
  };
}
