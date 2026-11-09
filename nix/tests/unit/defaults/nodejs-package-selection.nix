{ fixtures }:
{
  testNodejsIsNotInstalledAsAStandalonePackage = {
    expr = map (package: package.drvPath) (
      builtins.filter (package: (package.pname or null) == "nodejs")
        (fixtures.mkHome "x86_64-linux" [
          (fixtures.homeModule "common")
          { programs.nixvim.enable = true; }
        ]).config.home.packages
    );
    expected = [ ];
  };
}
