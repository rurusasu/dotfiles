{ inputs }:
let
  manifest = (import ../fixtures/packages.nix { inherit inputs; }).pnpmManifest;
in
{
  testNoPnpmPackagesAreDeclared = {
    expr = manifest.globalPackages;
    expected = [ ];
  };
}
