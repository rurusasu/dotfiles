{ fixtures }:
{
  testNodejsIsNotInstalledAsAStandalonePackage = {
    expr = map (package: package.drvPath) (
      builtins.filter (package: (package.pname or null) == "nodejs")
        (fixtures.mkHome "x86_64-linux" [
          (fixtures.homeModule "common")
          { programs.neovim.enable = true; }
        ]).config.home.packages
    );
    expected = [ ];
  };
}
