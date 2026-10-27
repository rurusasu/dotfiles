{ fixtures }:
{
  testNoPnpmPackagesAreDeclared = {
    expr = fixtures.pnpmManifest.globalPackages;
    expected = [ ];
  };
}
